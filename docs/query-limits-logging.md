# API-21 refusal log lines

Every request refused by the API-21 query-cost limits writes one log line
with the stable prefix `[api21_refusal]` followed by JSON:

```
[api21_refusal] {"kind":"page_size","path":"plants","argument":"first","requested":501,"limit":500,"operation_name":"Big","authenticated":false,"request_id":"..."}
[api21_refusal] {"kind":"depth","path":null,"argument":null,"requested":13,"limit":12,"operation_name":null,"authenticated":true,"request_id":"..."}
[api21_refusal] {"kind":"complexity","path":null,"argument":null,"requested":1280202,"limit":400000,"operation_name":null,"authenticated":false,"request_id":"..."}
```

- `kind`: `page_size` (connection first/last above 500), `depth` (max_depth 12)
  or `complexity` (max_complexity 400,000).
- `path` and `argument` are set for `page_size` only (for example
  `category.plants`, `first`).
- `operation_name` is present only when the client sent a plain GraphQL name.
- `authenticated` is a boolean; no identity, query text, variables or IP is
  ever logged. The client-facing error responses are unchanged.

Implementation: `Api21RefusalLogger`, called from
`Extensions::PageSizeLimitedConnectionExtension` and `GraphqlController`.

## CloudWatch Logs Insights

Count refusals by kind over the selected time range:

```
filter @message like /\[api21_refusal\]/
| parse @message '"kind":"*"' as kind
| stats count(*) as refusals by kind
| sort refusals desc
```

Per hour and authenticated flag:

```
filter @message like /\[api21_refusal\]/
| parse @message '"kind":"*"' as kind
| parse @message '"authenticated":*,' as authenticated
| stats count(*) as refusals by bin(1h), kind, authenticated
```
