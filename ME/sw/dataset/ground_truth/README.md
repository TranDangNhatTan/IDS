# Ground truth riêng của dự án

Gộp KDDTrain+.txt và KDDTest+.txt đầy đủ. Không cộng hai file subset để tránh nhân bản mẫu. Mỗi hàng model-ready có 41 feature và một nhãn gốc. Difficulty/provenance không phải feature.

Các vector 41 feature có nhiều nhãn trái ngược được đưa vào `quarantined_label_conflicts.csv`. Các vector trùng nhưng cùng nhãn được giữ một bản; chi tiết nằm trong `deduplicated_consistent_records.csv`.

Bộ này trộn train/test chuẩn của NSL-KDD, nên kết quả split mới chỉ có ý nghĩa nội bộ và không so sánh trực tiếp với benchmark chuẩn.
