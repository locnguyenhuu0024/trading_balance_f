from __future__ import annotations

import threading
import unittest
from unittest.mock import patch

from backend.okx import OKXClient, OKXError, OKXTransportError


class FakeResponse:
    def __init__(self, body: bytes, *, status: int = 200, retry_after: str | None = None):
        self.body = body
        self.status = status
        self.will_close = False
        self._retry_after = retry_after

    def read(self, size: int) -> bytes:
        return self.body[:size]

    def getheader(self, name: str) -> str | None:
        return self._retry_after if name.lower() == "retry-after" else None


class HTTPSConnectionPoolTests(unittest.TestCase):
    def test_sequential_reads_reuse_one_connection(self) -> None:
        connections = []

        class Connection:
            def __init__(self, host: str, *, timeout: float):
                self.host = host
                self.requests = 0
                self.closed = False
                connections.append(self)

            def request(self, method, path, *, body=None, headers=None):
                self.requests += 1

            def getresponse(self):
                return FakeResponse(b'{"code":"0","data":[]}')

            def close(self):
                self.closed = True

        with patch("backend.okx.http.client.HTTPSConnection", Connection):
            client = OKXClient("key", "secret", "passphrase")
            for _ in range(2):
                result = client.request(
                    "GET", "/api/v5/public/instruments", params={"instType": "SPOT"}, private=False
                )

        self.assertEqual(result["code"], "0")
        self.assertEqual(len(connections), 1)
        self.assertEqual(connections[0].requests, 2)
        self.assertFalse(connections[0].closed)

    def test_concurrent_requests_hold_exclusive_connection_leases(self) -> None:
        rendezvous = threading.Barrier(2)
        connections = []
        seen: list[int] = []
        errors: list[BaseException] = []
        lock = threading.Lock()

        class Connection:
            def __init__(self, host: str, *, timeout: float):
                self.number = len(connections) + 1
                connections.append(self)

            def request(self, method, path, *, body=None, headers=None):
                with lock:
                    seen.append(self.number)
                rendezvous.wait(timeout=3)

            def getresponse(self):
                return FakeResponse(b'{"code":"0","data":[]}')

            def close(self):
                return None

        with patch.object(OKXClient, "MAX_CONNECTIONS", 2):
            with patch("backend.okx.http.client.HTTPSConnection", Connection):
                client = OKXClient("key", "secret", "passphrase")

                def read() -> None:
                    try:
                        client.request("GET", "/api/v5/public/instruments", private=False)
                    except BaseException as error:
                        errors.append(error)

                workers = [threading.Thread(target=read) for _ in range(2)]
                for worker in workers:
                    worker.start()
                for worker in workers:
                    worker.join(5)

        self.assertTrue(all(not worker.is_alive() for worker in workers))
        self.assertEqual(errors, [])
        self.assertEqual(len(connections), 2)
        self.assertEqual(len(set(seen)), 2)

    def test_four_read_leases_leave_pool_capacity_for_one_write(self) -> None:
        read_barrier = threading.Barrier(4)
        release_reads = threading.Event()
        all_reads_held = threading.Event()
        write_entered = threading.Event()
        connections = []
        methods: list[str] = []
        lock = threading.Lock()
        errors: list[BaseException] = []

        class Connection:
            def __init__(self, host: str, *, timeout: float):
                self.number = len(connections) + 1
                self.closed = False
                connections.append(self)

            def request(self, method, path, *, body=None, headers=None):
                with lock:
                    methods.append(method)
                if method == "GET":
                    read_barrier.wait(timeout=3)
                    all_reads_held.set()
                    if not release_reads.wait(5):
                        raise TimeoutError("test GET lease release timed out")
                else:
                    write_entered.set()

            def getresponse(self):
                return FakeResponse(b'{"code":"0","data":[]}')

            def close(self):
                self.closed = True

        with patch("backend.okx.http.client.HTTPSConnection", Connection):
            client = OKXClient("key", "secret", "passphrase")

            def read() -> None:
                try:
                    client.request("GET", "/api/v5/public/instruments", private=False)
                except BaseException as error:
                    errors.append(error)

            readers = [threading.Thread(target=read) for _ in range(4)]
            for worker in readers:
                worker.start()
            try:
                self.assertTrue(all_reads_held.wait(3))
                client.request("POST", "/api/v5/trade/order", body={"instId": "BTC-USDT-SWAP"})
                self.assertTrue(write_entered.is_set())
                self.assertEqual(len(connections), 5)
                self.assertEqual(len({id(connection) for connection in connections}), 5)
            finally:
                release_reads.set()
            for worker in readers:
                worker.join(5)

        self.assertEqual(errors, [])
        self.assertEqual(methods.count("GET"), 4)
        self.assertEqual(methods.count("POST"), 1)

    def test_oversized_response_discards_connection_without_post_replay(self) -> None:
        connections = []
        responses = [b"A" * 17, b'{"code":"0"}']

        class Connection:
            def __init__(self, host: str, *, timeout: float):
                self.number = len(connections) + 1
                self.closed = False
                self.requests = 0
                connections.append(self)

            def request(self, method, path, *, body=None, headers=None):
                self.requests += 1

            def getresponse(self):
                return FakeResponse(responses[self.number - 1])

            def close(self):
                self.closed = True

        with patch.object(OKXClient, "MAX_RESPONSE_BYTES", 16):
            with patch("backend.okx.http.client.HTTPSConnection", Connection):
                client = OKXClient("key", "secret", "passphrase")
                with self.assertRaises(OKXTransportError):
                    client.request("POST", "/api/v5/trade/order", body={"instId": "BTC-USDT-SWAP"})
                self.assertEqual(connections[0].requests, 1)
                self.assertTrue(connections[0].closed)
                self.assertEqual(client._connection_pool._connection_count, 0)

                next_response = client.request("GET", "/api/v5/public/instruments", private=False)
                self.assertEqual(next_response["code"], "0")

        self.assertEqual(len(connections), 2)
        self.assertEqual(connections[1].requests, 1)

    def test_top_level_rate_limit_preserves_http_metadata(self) -> None:
        class Connection:
            def __init__(self, host: str, *, timeout: float):
                pass

            def request(self, method, path, *, body=None, headers=None):
                return None

            def getresponse(self):
                return FakeResponse(b'{"code":"50011","data":[]}', retry_after="29")

            def close(self):
                return None

        with patch("backend.okx.http.client.HTTPSConnection", Connection):
            client = OKXClient("key", "secret", "passphrase")
            with self.assertRaises(OKXError) as raised:
                client.request("GET", "/api/v5/account/balance")

        self.assertEqual(raised.exception.error_code, "50011")
        self.assertEqual(raised.exception.http_status, 200)
        self.assertEqual(raised.exception.retry_after, "29")


if __name__ == "__main__":
    unittest.main()
