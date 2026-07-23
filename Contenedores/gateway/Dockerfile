# PASARELA
# Los alumnos y sus reglas sudo los anaden los scripts de aprovisionamiento en caliente.
FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server sudo docker.io ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/sshd

RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
         -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Password auth solo para el mock (en el servidor real: claves SSH).
RUN sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]

# docker build -t lab-gateway .
# docker run -d --name lab-gateway -p 2222:22 -v /var/run/docker.sock:/var/run/docker.sock lab-gateway