FROM ubuntu

RUN apt-get update && apt-get install -y \
    haproxy \
    default-jdk \
    gradle \
    maven \
    iputils-ping \
    iputils-arping \
    iproute2 \
    curl \
    net-tools \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --break-system-packages flask scapy tensorflow

WORKDIR /app

COPY *.pkl .

COPY use_me.py .

COPY <<EOF /app/server.py
from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def home():
    port = os.getenv('FLASK_PORT', '5000')
    return f'''
    <html>
        <head>
            <style>
                body {{
                    background-color: {os.getenv('BG_COLOR', 'lightgray')};
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    font-size: 48px;
                    color: black;
                }}
            </style>
        </head>
        <body>
            Port: {port}
        </body>
    </html>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('FLASK_PORT', 5000)))
EOF

COPY <<EOF /usr/local/etc/haproxy/haproxy.cfg

frontend flask_frontend
    bind *:80
    default_backend flask_backend
    stick-table type ip size 200k expire 30s store http_req_rate(30s)
    http-request deny if { src_get_gpc0 gt 100 }
    acl toomany_conn src_conn_cur gt 20
    tcp-request content reject if toomany_conn
    timeout client 30s
    timeout http-keep-alive 5s

backend flask_backend
    balance roundrobin
    option httpchk
    server flask1 127.0.0.1:5001 check
    server flask2 127.0.0.1:5002 check
    server flask3 127.0.0.1:5003 check

listen stats
    mode http
    bind *:8405
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /
    stats refresh 10s
EOF

EXPOSE 80 8405

CMD python server.py & \
    FLASK_PORT=5001 BG_COLOR=lightblue python3 server.py & \
    FLASK_PORT=5002 BG_COLOR=lightgreen python3 server.py & \
    FLASK_PORT=5003 BG_COLOR=lightcoral python3 server.py & \
    haproxy -f /usr/local/etc/haproxy/haproxy.cfg -db

