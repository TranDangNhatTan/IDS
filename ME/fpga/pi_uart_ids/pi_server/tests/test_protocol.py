import unittest
from protocol import *
class ProtocolTests(unittest.TestCase):
 def test_crc_contract_vector(self): self.assertEqual(crc16_ccitt_false(b"123456789"), 0x29b1)
 def test_feature_round_trip(self):
  values=[0,1,MAX_FEATURE]+[i*137 for i in range(25)]
  self.assertEqual(unpack_features(pack_features(values)),values)
 def test_frame_round_trip(self):
  wire=encode_frame(FEATURE_TYPE,0x1234,pack_features([0]*28)); self.assertEqual(decode_frame(wire)[0:2],(FEATURE_TYPE,0x1234))
 def test_crc_rejected(self):
  wire=bytearray(encode_frame(RESULT_TYPE,1,bytes(7))); wire[2]^=1
  with self.assertRaises(ProtocolError): decode_frame(bytes(wire))
