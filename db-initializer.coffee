
exports.init = (client) ->
  client.query("""
  CREATE TABLE urls
  (
    id serial PRIMARY KEY,
    long_url text NOT NULL
      CHECK(long_url ~ '^https?://'),
    hash character varying(16) UNIQUE NOT NULL
      CHECK(hash ~* '^[0-9a-z]+$'),
    ip_address character varying(16) NOT NULL
      CHECK(ip_address ~ '^\\d{1,3}(?:\\.\\d{1,3}){3}$'),
    network_prefix integer NOT NULL
      CHECK(0 < network_prefix AND network_prefix <= 32)
  )
  """, -> ) # ignore error