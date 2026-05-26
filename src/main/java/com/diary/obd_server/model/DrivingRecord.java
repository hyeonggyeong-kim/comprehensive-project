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

    @Column(columnDefinition = "LONGTEXT") // 대용량 텍스트 지정을 위해 필수!
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
    public String getDetailedData() { return detailedData; }
    public void setDetailedData(String detailedData) { this.detailedData = detailedData; }
}