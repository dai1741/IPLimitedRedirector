
exports.init = (client) ->
  client.query("""
  CREATE TABLE urls
  (
     id serial NOT NULL,
     long_url text NOT NULL,
     hash character varying(16) NOT NULL,
     ip_address character varying(16) NOT NULL,
     network_prefix integer NOT NULL,
     PRIMARY KEY (id),
     UNIQUE (id, hash)
  )
  """, -> ) # ignore error