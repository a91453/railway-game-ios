# tdx-batch

Fetches a whole list of TDX paths in one run of `.github/workflows/tdx-batch.yml`
(Actions → Fetch TDX batch → Run workflow on `main`, `list` = a file in `lists/`),
where `tdx-check.yml` asks one path per run. The owner's key stays in the
repository secrets `TDX_CLIENT_ID` / `TDX_CLIENT_SECRET`; nothing here sees it.

The run's artifact `tdx-batch` holds `<name>.json.gz` for each path and
`manifest.json` (path, HTTP status, bytes, records, fetch time). The raw answers
go to the owner's private reference repository, never into this public one
(政府資料開放授權條款第 1 版; credit 「交通部運輸資料流通服務平臺（TDX）」).

TDX charges points by the bytes it sends, `/api/basic/` too (about 6.5 points a
GB, read from the owner's usage page on 2026-11-20), so a list says roughly how
big it is before it is run.

- `lists/bus.txt`: city buses of all 22 places and the highway coaches
  (`InterCity`): route, stop, stop order, shape, timetable, fare, operator.
- `lists/ship-air.txt`: ferries (ports, routes, timetables, fares) and flights
  (airports, airlines, domestic and international timetables). Some of these
  paths are probes; a 404 is recorded and the run goes on.
