pkgs:
pkgs.runCommandNoCC "self-signed-cert" { buildInputs = [ pkgs.openssl ]; } ''
  mkdir $out
  openssl req -x509 -newkey rsa:4096 -sha256 -days 365000 -nodes \
    -keyout $out/server.key \
    -out $out/server.crt \
    -subj "/CN=*"
''
