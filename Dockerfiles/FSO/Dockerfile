FROM ubuntu:22.04

RUN apt update && apt install -y \
    gcc \
    gdb \
    make \
    valgrind \
    nano \
    vim

CMD ["/bin/bash"]

# docker build  -t fso .
# docker start fso
# docker exec -it fso bash