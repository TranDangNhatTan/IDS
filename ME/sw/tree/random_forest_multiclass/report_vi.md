# random_forest — dự đoán tên loại tấn công

Model chọn bằng validation macro-F1: max_depth=12; macro-F1 validation=75.46%.

Cả hai model dùng cùng split 80/20, seed 42, nhãn gốc đa lớp, one-hot chỉ fit trên train khi chọn cấu hình, class_weight=balanced. Split có ít nhất một mẫu mỗi lớp trong cả train/validation; lớp rất hiếm có 1 mẫu validation nên metric có độ bất định lớn.

KDDTest+ là benchmark đã xem ở lần chạy trước. Không dùng kết quả của lần đánh giá này để đổi cấu hình. Cần dữ liệu độc lập mới để đánh giá phiên bản được phát triển sau khi đã xem benchmark.

Train có 23 lớp; test có 17 nhãn chưa xuất hiện trong train, tổng 3750 mẫu. Model phân loại đóng không thể dự đoán đúng tên lớp chưa được học.

## Metric đa lớp

| Metric | Giá trị |
|---|---:|
| accuracy | 71.82% |
| macro_f1 | 25.53% |
| macro_f1_test_present_classes | 26.88% |
| weighted_f1 | 62.36% |

Macro-F1 mặc định tính trên hợp các nhãn train/test (kể cả lớp không có mẫu test); có thêm macro-F1 chỉ trên lớp hiện diện trong test. Weighted-F1 có trọng số theo support nên dễ bị lớp lớn chi phối.

## Phát hiện có tấn công (gộp từ dự đoán đa lớp)

| Metric | Giá trị |
|---|---:|
| precision_attack | 96.39% |
| recall_attack | 62.56% |
| f1_attack | 75.87% |
| false_positive_rate | 3.10% |
| accuracy | 77.35% |

## Các kiểu lỗi

- correct_type: 16190
- missed_attack: 4805
- wrong_attack_type: 1248
- false_alarm: 301

`false_alarm`: normal bị gọi thành tấn công. `missed_attack`: tấn công bị gọi normal. `wrong_attack_type`: phát hiện có tấn công nhưng gọi sai tên loại. `correct_type`: đúng tên loại (bao gồm normal).

## Precision / recall / F1 từng loại

| Nhãn | Precision | Recall | F1 | Test support | Train support |
|---|---:|---:|---:|---:|---:|
| apache2 | 0.00% | 0.00% | 0.00% | 737 | 0 |
| back | 99.43% | 97.49% | 98.45% | 359 | 956 |
| buffer_overflow | 14.29% | 5.00% | 7.41% | 20 | 30 |
| ftp_write | 0.00% | 0.00% | 0.00% | 3 | 8 |
| guess_passwd | 0.00% | 0.00% | 0.00% | 1231 | 53 |
| httptunnel | 0.00% | 0.00% | 0.00% | 133 | 0 |
| imap | 0.00% | 0.00% | 0.00% | 1 | 11 |
| ipsweep | 75.00% | 97.87% | 84.92% | 141 | 3599 |
| land | 100.00% | 100.00% | 100.00% | 7 | 18 |
| loadmodule | 0.00% | 0.00% | 0.00% | 2 | 9 |
| mailbomb | 0.00% | 0.00% | 0.00% | 293 | 0 |
| mscan | 0.00% | 0.00% | 0.00% | 996 | 0 |
| multihop | 0.00% | 0.00% | 0.00% | 18 | 7 |
| named | 0.00% | 0.00% | 0.00% | 17 | 0 |
| neptune | 94.16% | 98.75% | 96.40% | 4657 | 41214 |
| nmap | 54.07% | 100.00% | 70.19% | 73 | 1493 |
| normal | 66.20% | 96.90% | 78.66% | 9711 | 67343 |
| perl | 50.00% | 50.00% | 50.00% | 2 | 3 |
| phf | 100.00% | 50.00% | 66.67% | 2 | 4 |
| pod | 58.21% | 95.12% | 72.22% | 41 | 201 |
| portsweep | 68.64% | 96.18% | 80.11% | 157 | 2931 |
| processtable | 0.00% | 0.00% | 0.00% | 685 | 0 |
| ps | 0.00% | 0.00% | 0.00% | 15 | 0 |
| rootkit | 0.00% | 0.00% | 0.00% | 13 | 10 |
| saint | 0.00% | 0.00% | 0.00% | 319 | 0 |
| satan | 60.08% | 99.73% | 74.99% | 735 | 3633 |
| sendmail | 0.00% | 0.00% | 0.00% | 14 | 0 |
| smurf | 99.70% | 100.00% | 99.85% | 665 | 2646 |
| snmpgetattack | 0.00% | 0.00% | 0.00% | 178 | 0 |
| snmpguess | 0.00% | 0.00% | 0.00% | 331 | 0 |
| spy | 0.00% | 0.00% | 0.00% | 0 | 2 |
| sqlattack | 0.00% | 0.00% | 0.00% | 2 | 0 |
| teardrop | 24.49% | 100.00% | 39.34% | 12 | 892 |
| udpstorm | 0.00% | 0.00% | 0.00% | 2 | 0 |
| warezclient | 0.00% | 0.00% | 0.00% | 0 | 890 |
| warezmaster | 76.92% | 1.06% | 2.09% | 944 | 20 |
| worm | 0.00% | 0.00% | 0.00% | 2 | 0 |
| xlock | 0.00% | 0.00% | 0.00% | 9 | 0 |
| xsnoop | 0.00% | 0.00% | 0.00% | 4 | 0 |
| xterm | 0.00% | 0.00% | 0.00% | 13 | 0 |

![Confusion matrix](confusion_matrix.png)

Xem `confusion_pairs.csv` để biết loại A bị gọi thành loại B bao nhiêu lần; `misclassified_records.csv` có từng dòng sai, nhãn thật/dự đoán và 41 đặc trưng. `source_line_one_based` trỏ tới dòng trong KDDTest+.txt.

Số cây: 200; tổng node: 112536; dung lượng model: 28032842 byte. Thời gian fit cuối: 10.78s; dự đoán test: 0.323s. Thời gian trên CPU này không phải benchmark FPGA.
