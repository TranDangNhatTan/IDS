# Điều tra nguyên nhân nhầm lẫn và bỏ sót

Phân tích này đọc hai model và dự đoán đã lưu; không fit lại, không đổi ngưỡng và không chọn cấu hình dựa trên KDDTest+. Vì KDDTest+ đã được xem, các phát hiện là chẩn đoán benchmark, không phải bằng chứng trên holdout mới.

## Kết luận nguyên nhân

1. **Open-set / nhãn chưa học:** train có 23 tên lớp, test có 38, giao nhau 21. Có 17 nhãn chỉ xuất hiện trong test (3750 mẫu). Classifier đóng không thể xuất đúng một tên chưa có trong classes_.
2. **Mất cân bằng và support quá nhỏ:** nhiều lớp chỉ có 2–53 mẫu train. `guess_passwd` có 53 train nhưng 1.231 test; `warezmaster` có 20 train nhưng 944 test. Một hoặc vài mẫu validation ở lớp hiếm làm macro-F1 lựa chọn model dao động mạnh.
3. **Concept/covariate shift:** cùng một tên lớp có phân bố đặc trưng khác giữa train và test. File feature_shift ghi KS statistic; đây là bằng chứng về khác biệt phân bố, không tự chứng minh nguyên nhân vật lý.
4. **Mục tiêu đa lớp trực tiếp gây bỏ sót:** `predict` chọn lớp có xác suất lớn nhất. Với Random Forest, normal có thể là lớp đơn lớn nhất dù tổng xác suất các lớp attack lớn hơn. 3.134/4.805 mẫu attack bị RF gọi normal có P(normal) < 0,5. Vì vậy nên tách cổng normal/attack khỏi bước đặt tên.
5. **Decision Tree quá tự tin:** cây không giới hạn tạo lá gần thuần, cho xác suất 1,0 cả với nhiều lỗi. Xác suất lá này không được hiệu chỉnh và không nên xem là độ tin cậy thực.
6. **Không phải lỗi category chưa biết:** protocol/service/flag trong test đều thuộc tập category đã có trong train. `handle_unknown=ignore` không phải nguyên nhân chính của benchmark này.

## Kết quả theo họ tấn công

Gộp tên về normal/DoS/Probe/R2L/U2R giúp đo mức hữu ích khi tên cụ thể chưa có trong train. Đây là phép đánh giá bổ sung, không thay đổi model.

| Model | Family accuracy | Family macro-F1 | DoS recall | Probe recall | R2L recall | U2R recall |
|---|---:|---:|---:|---:|---:|---:|
| decision_tree_multiclass | 76.61% | 56.12% | 80.27% | 66.50% | 9.77% | 17.91% |
| random_forest_multiclass | 75.95% | 55.98% | 76.80% | 61.46% | 16.92% | 10.45% |

## Dấu hiệu lệch đặc trưng mạnh nhất

| Loại | Feature | KS | Median train | Median test |
|---|---|---:|---:|---:|
| guess_passwd | hot | 0.981 | 1 | 0 |
| guess_passwd | dst_host_serror_rate | 0.981 | 0.06 | 0 |
| guess_passwd | dst_host_srv_serror_rate | 0.978 | 0.06 | 0 |
| guess_passwd | dst_host_rerror_rate | 0.960 | 0.94 | 0.02 |
| guess_passwd | dst_host_srv_rerror_rate | 0.951 | 0.94 | 0 |
| warezmaster | dst_bytes | 0.949 | 5.151e+06 | 593 |
| warezmaster | src_bytes | 0.899 | 0 | 160 |
| warezmaster | duration | 0.757 | 9 | 281 |
| warezmaster | dst_host_same_src_port_rate | 0.579 | 1 | 0.055 |
| warezmaster | dst_host_same_srv_rate | 0.575 | 1 | 0.42 |

KS gần 1 nghĩa phân bố thực nghiệm rất khác. P-value chỉ được lưu để tham khảo; với nhiều phép thử và dữ liệu lệch lớp, không dùng nó làm tiêu chí chọn model.

## Chọn thuật toán

Nếu mục tiêu ưu tiên FPGA và không bỏ sót, **Decision Tree hiện hợp lý hơn trong hai model đã chạy**: recall attack 67,66% so với RF 62,56%, model 1 cây/1.003 node/0,26 MB so với 200 cây/112.536 node/28,03 MB. RF có macro-F1 theo tên tốt hơn (26,88% so với 24,87%) và ít báo động nhầm hơn một chút, nhưng chi phí lớn hơn nhiều và bỏ sót thêm 655 attack.

Thiết kế hợp lý nhất là **phân cấp hai tầng**, thay vì một classifier đa lớp trực tiếp:

1. Tầng 1: binary normal/attack, chọn threshold trên validation theo chi phí FN cao hơn FP; báo cả score. Đây là tầng triển khai FPGA.
2. Tầng 2: chỉ chạy trên mẫu đã được tầng 1 báo attack; phân loại DoS/Probe/R2L/U2R trước, sau đó mới đặt tên cụ thể nếu đủ dữ liệu.
3. Nếu score hoặc khoảng cách phân bố không đủ chắc, trả `unknown_attack`; không ép về normal hay một tên đã biết.

Có thể dùng Decision Tree/pruned small forest cho tầng 1 trên FPGA; nếu có CPU/MCU phía sau, dùng Random Forest nhỏ hoặc gradient-boosted trees cho tầng đặt tên. Nếu tất cả phải ở FPGA, thử ensemble 8–32 cây nông và so sánh Pareto recall/FPR/node count; RF 200 cây hiện tại quá lớn so với lợi ích đo được.

## Thứ tự cải tiến nên thực hiện

- Đổi mục tiêu chọn tầng 1 sang recall attack với ràng buộc FPR, ví dụ tối đa FPR cho phép rồi chọn recall cao nhất. Chọn threshold bằng out-of-fold validation, không dùng test.
- Dùng repeated stratified cross-validation cho lớp đủ mẫu; với lớp 2–10 mẫu, cần thu thập thêm hoặc gộp theo family. Không thể sửa thiếu dữ liệu chỉ bằng class_weight/SMOTE.
- Huấn luyện family classifier và unknown detector. Đánh giá riêng known/unknown, confusion family và false-negative rate.
- Thử `min_samples_leaf`, pruning `ccp_alpha`, class/cost weights và cây nông; báo đường Pareto giữa recall, FPR, macro-F1, node count và dung lượng.
- Với RF, giảm còn 8/16/32/64 cây, tune `max_depth`, `min_samples_leaf`, `max_features`; hiệu chỉnh xác suất bằng validation trước khi đặt threshold.
- Không random oversample trước split. Nếu dùng sampling/SMOTE, chỉ áp dụng bên trong từng fold train và ưu tiên dữ liệu thật cho R2L/U2R hiếm.
- Tạo holdout mới hoặc dùng dataset khác sau khi chốt pipeline, vì KDDTest+ đã tham gia phân tích.

Các file CSV trong thư mục này chứa family confusion matrix, độ tin cậy theo loại lỗi, coverage category, support shift và feature shift.
