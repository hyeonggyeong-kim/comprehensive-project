package com.diary.obd_server.model;

import jakarta.persistence.*;

@Entity
@Table(name = "driving_records")
public class DrivingRecord {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String userEmail;
    private String startTime;
    private String endTime;
    private Double avgSpeed;
    private Double avgRpm;

    // [추가] FastAPI에서 받아온 AI 위험도 점수 저장
    private Double riskScore;

    // 🟢 [여기에 추가됨!] 연비 등급 라벨 저장 (예: "안전 (Eco)")
    // 🟢
    private String riskLabel;

    @Column(columnDefinition = "LONGTEXT")
    private String detailedData;

    // Getter & Setter
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getUserEmail() { return userEmail; }
    public void setUserEmail(String userEmail) { this.userEmail = userEmail; }
    public String getStartTime() { return startTime; }
    public void setStartTime(String startTime) { this.startTime = startTime; }
    public String getEndTime() { return endTime; }
    public void setEndTime(String endTime) { this.endTime = endTime; }
    public Double getAvgSpeed() { return avgSpeed; }
    public void setAvgSpeed(Double avgSpeed) { this.avgSpeed = avgSpeed; }
    public Double getAvgRpm() { return avgRpm; }
    public void setAvgRpm(Double avgRpm) { this.avgRpm = avgRpm; }

    public Double getRiskScore() { return riskScore; }
    public void setRiskScore(Double riskScore) { this.riskScore = riskScore; }

    // 🟢 [여기에 추가됨!] riskLabel의 Getter & Setter
    public String getRiskLabel() { return riskLabel; }
    public void setRiskLabel(String riskLabel) { this.riskLabel = riskLabel; }

    public String getDetailedData() { return detailedData; }
    public void setDetailedData(String detailedData) { this.detailedData = detailedData; }
}