
exports.init = (client, ex1, ex2) ->
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
  """, (err)->
    unless err # new table created
      # example
      for ex in [
        ["http://exapmle.com", ex1, "0.0.0.0", 1]
        ["http://exapmle.com", ex2, "128.0.0.0", 1]
      ]
        client.query('INSERT INTO urls(
            long_url, hash, ip_address, network_prefix) VALUES($1, $2, $3, $4)',
            ex, (err, result) ->)
  )
  