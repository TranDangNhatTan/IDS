import unittest
from features import FeatureMapper, PacketRecord
class FeatureTests(unittest.TestCase):
 def test_udp_mapping_uses_rtl_order_and_scaling(self):
  record=PacketRecord(1,"10.0.0.1","10.0.0.2",12345,40000,b"x"*10,1000)
  values=FeatureMapper().map(record)
  self.assertEqual(len(values),28)
  self.assertEqual(values[:9],[0,3,45,1,250,0,0,0,0])
  self.assertEqual(values[9:20],[0,0,0,0,0,0,0,0,0,0,0])
