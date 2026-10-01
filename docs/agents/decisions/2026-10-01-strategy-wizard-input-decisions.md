# Strategy wizard input decisions

Date: 2026-10-01
Status: RESOLVED

| ID | Decision | Evidence |
| --- | --- | --- |
| D-001 | Treat a single comma in the margin field as a decimal separator, and send a dot-decimal string to the backend. | The user confirmed iPhone numeric keyboard enters `100,0` in Total Margin and the error appears after pressing Review Orders. |
| D-002 | Keep backend rejection of JSON floating-point values for financial prices; serialize selected levels and entries as decimal strings in Flutter. | `backend/strategy.py` intentionally rejects floats; existing backend fixtures already send strings. |

No thousands-separator parsing or currency suffix is authorized. Search uses the already loaded instrument catalog and makes no additional market request until a contract is selected.
