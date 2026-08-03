# Bundle the managed OAuth client with releases

Each `pumd` release will contain the managed Google Desktop OAuth client identity instead of fetching authorization configuration from a `pumd`-hosted endpoint at runtime. Desktop client identity is extractable from a distributed CLI regardless, while release bundling avoids a new availability dependency and remote configuration trust path; client rotation will require upgrading `pumd`, and a revoked client will produce explicit upgrade guidance.
