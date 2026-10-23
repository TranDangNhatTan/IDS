import unittest
from protocol import *
from uart_client import UartClient
class FakeSerial:
 def __init__(self, reply): self.reply=bytearray(reply); self.writes=[]
 def write(self, value): self.writes.append(value)
 def flush(self): pass
 def read(self, _): return bytes([self.reply.pop(0)]) if self.reply else b""
class UartTests(unittest.TestCase):
 def test_known_result(self):
  got=[]; client=UartClient({"uart_retry_limit":0,"uart_timeout_ms":20},lambda *v:got.append(v),lambda *_:None)
  client.serial=FakeSerial(encode_frame(RESULT_TYPE,7,bytes([3,0x34,0x12,9,0,2,0])))
  self.assertTrue(client.transact(7,[0]*28)); self.assertEqual(got[0][1]["leaf_node"],0x1234)
