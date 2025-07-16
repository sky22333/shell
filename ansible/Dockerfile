FROM alpine

RUN apk add --update --no-cache ansible bash openssh sshpass rsync py3-passlib

COPY ansible /etc/ansible

ENTRYPOINT []
CMD ["ansible", "--help"]