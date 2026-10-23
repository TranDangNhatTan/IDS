#!/usr/bin/env python3
"""Send PING packets to the ACG525 onboard-RGMII demo and verify ACK1 replies."""
import argparse, socket, struct, threading, time

def egress_ip(target, port):
    probe=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    try:
        probe.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
        probe.connect((target,port))
        return probe.getsockname()[0]
    finally: probe.close()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--target',default='192.168.50.255')
    ap.add_argument('--port',type=int,default=55002)
    ap.add_argument('--reply-port',type=int,default=55003)
    ap.add_argument('--count',type=int,default=10)
    ap.add_argument('--interval-ms',type=float,default=100.0)
    ap.add_argument('--timeout-ms',type=float,default=800.0)
    ap.add_argument('--self-test',action='store_true',help='run the client against a local ACK1 mock; no FPGA needed')
    a=ap.parse_args()
    stop_mock=threading.Event()
    if a.self_test:
        a.target='127.0.0.1'; a.port=55102; a.reply_port=55103; a.count=3
        def mock():
            s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(('127.0.0.1',a.port)); s.settimeout(.1)
            while not stop_mock.is_set():
                try: payload,origin=s.recvfrom(64)
                except socket.timeout: continue
                if len(payload)==8 and payload[:4]==b'PING': s.sendto(b'ACK1'+payload[4:],origin)
            s.close()
        threading.Thread(target=mock,daemon=True).start()
    elif not a.target.endswith('.255'):
        raise SystemExit('This FPGA demo has no ARP: target must be the /24 broadcast address.')
    sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
    sock.bind(('0.0.0.0',a.reply_port))
    sock.settimeout(a.timeout_ms/1000.0)
    print(f'UDP_ECHO_CHECK target={a.target}:{a.port}, listen=0.0.0.0:{a.reply_port}, egress={egress_ip(a.target,a.port)}')
    pending=set(); received=set(); start=time.perf_counter()
    for seq in range(a.count):
        sock.sendto(b'PING'+struct.pack('<I',seq),(a.target,a.port)); pending.add(seq)
        until=time.monotonic()+a.interval_ms/1000.0
        while time.monotonic()<until:
            try: data,addr=sock.recvfrom(256)
            except socket.timeout: break
            if len(data)==8 and data[:4]==b'ACK1':
                got=struct.unpack_from('<I',data,4)[0]
                if got in pending: received.add(got); print(f'ACK1 sequence={got} from={addr[0]}:{addr[1]}')
            else: print(f'Unexpected UDP {len(data)} bytes from {addr}')
    deadline=time.monotonic()+a.timeout_ms/1000.0
    while pending-received and time.monotonic()<deadline:
        try: data,addr=sock.recvfrom(256)
        except socket.timeout: break
        if len(data)==8 and data[:4]==b'ACK1': received.add(struct.unpack_from('<I',data,4)[0])
    elapsed=time.perf_counter()-start; missing=sorted(pending-received)
    print(f'RESULT sent={len(pending)} ack={len(received)} missing={missing} elapsed_s={elapsed:.3f}')
    stop_mock.set()
    raise SystemExit(0 if not missing else 1)
if __name__=='__main__': main()
