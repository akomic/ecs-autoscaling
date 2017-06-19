FROM python:2.7.13

LABEL maintainer "Alen Komic"

ADD lifecycle.py /app/

RUN pip install boto3

ENTRYPOINT ["/app/lifecycle.py"]
