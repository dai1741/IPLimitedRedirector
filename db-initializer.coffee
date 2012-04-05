
exports.init = (client, ex1, ex2) ->
  client.query("""
  CREATE TABLE urls
  (
    id serial PRIMARY KEY,
    long_url text NOT NULL,
    hash character varying(16) UNIQUE NOT NULL,
    ip_address character varying(16) NOT NULL,
    network_prefix integer NOT NULL
  )
  """, (err)->
    unless err # new table created
      # example
      for ex in [
        ["http://example.com", ex1, "0.0.0.0", 1]
        ["http://example.com", ex2, "128.0.0.0", 1]
      ]
        client.query('INSERT INTO urls(
            long_url, hash, ip_address, network_prefix) VALUES($1, $2, $3, $4)',
            ex, (err, result) ->)
  )
  