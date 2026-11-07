# Binance read proxy for the web app

Browsers block Binance Spot and Margin reads because `api.binance.com` does not allow the `X-MBX-APIKEY` header in CORS. This nginx location lets `https://app.tradingbalancef.com` read those routes through the VPS.

What passes through: the API key header, the signed query and Binance's response. The secret stays on the device, and only GET is forwarded. The server stores nothing, and this location writes no access log. Use a read-only API key.

This is a user-owned server change. It does not touch the backend application or its worker.

## 1. Check that Binance accepts the VPS

Run on the VPS:

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://api.binance.com/api/v3/ping
```

`200` means continue. `451` or `403` means Binance blocks this server's location; stop here.

## 2. Add the location

Target: the `server` block that serves `api.tradingbalancef.com`. Add this inside it, before any catch-all `location /`:

```nginx
# Read-only Binance Spot and Margin proxy for the web app. GET only, nothing stored.
location ~ ^/binance-proxy/(?<binance_path>api/v3/(?:account|openOrders|allOrders)|sapi/v1/margin/(?:account|isolated/account|openOrders|allOrders))$ {
    access_log off;

    if ($http_origin != "https://app.tradingbalancef.com") {
        return 403;
    }
    if ($request_method = OPTIONS) {
        add_header Access-Control-Allow-Origin "https://app.tradingbalancef.com" always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "X-MBX-APIKEY" always;
        add_header Access-Control-Max-Age "600" always;
        add_header Vary "Origin" always;
        return 204;
    }
    if ($request_method != GET) {
        return 405;
    }

    resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;
    resolver_timeout 5s;
    set $binance_upstream https://api.binance.com;

    proxy_pass $binance_upstream/$binance_path$is_args$args;
    proxy_http_version 1.1;
    proxy_ssl_server_name on;
    proxy_ssl_verify on;
    proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
    proxy_set_header Host api.binance.com;
    proxy_set_header Connection "";
    proxy_set_header Origin "";
    proxy_set_header Referer "";
    proxy_set_header Cookie "";
    proxy_set_header X-Forwarded-For "";
    proxy_set_header X-Real-IP "";
    proxy_set_header CF-Connecting-IP "";
    proxy_set_header True-Client-IP "";
    proxy_connect_timeout 5s;
    proxy_read_timeout 15s;
    proxy_buffering off;
    proxy_no_cache 1;
    proxy_cache_bypass 1;

    proxy_hide_header Access-Control-Allow-Origin;
    proxy_hide_header Access-Control-Allow-Methods;
    proxy_hide_header Access-Control-Allow-Headers;
    proxy_hide_header Access-Control-Allow-Credentials;
    proxy_hide_header Set-Cookie;
    add_header Access-Control-Allow-Origin "https://app.tradingbalancef.com" always;
    add_header Access-Control-Expose-Headers "Retry-After, X-MBX-USED-WEIGHT-1M" always;
    add_header Cache-Control "no-store" always;
    add_header Vary "Origin" always;
}
```

`proxy_ssl_trusted_certificate` uses the Ubuntu path. Then:

```sh
sudo nginx -t && sudo systemctl reload nginx
```

This snippet has not been run through `nginx -t` yet: no nginx was available where it was written.

## 3. Verify, with a dummy key

Expect a Binance JSON error such as `-2008` or `-2014`, which proves the request reached Binance, plus `access-control-allow-origin: https://app.tradingbalancef.com`:

```sh
curl -si -H 'Origin: https://app.tradingbalancef.com' -H 'X-MBX-APIKEY: dummy' https://api.tradingbalancef.com/binance-proxy/sapi/v1/margin/account | grep -iE '^HTTP|access-control-allow-origin|code'
```

Another origin must get `403`:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H 'Origin: https://evil.example' https://api.tradingbalancef.com/binance-proxy/api/v3/account
```

A route outside the list must not reach Binance:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H 'Origin: https://app.tradingbalancef.com' https://api.tradingbalancef.com/binance-proxy/api/v3/order
```

## 4. Build the web app with the proxy

```sh
flutter build web --no-pub --release --dart-define=BINANCE_PROXY_URL=https://api.tradingbalancef.com/binance-proxy
```

Without this define the web app keeps showing `Spot và Margin chỉ có trên ứng dụng`.

## Rollback

Remove the location and reload nginx. The web app then shows Spot and Margin as unavailable and USDⓈ-M keeps working.
