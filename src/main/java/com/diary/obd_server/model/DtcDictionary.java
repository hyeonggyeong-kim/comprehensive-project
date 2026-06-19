package com.diary.obd_server.model;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "dtc_dictionary")
public class DtcDictionary {

    @Id
    private String code;        // 고장 코드 (예: P0100)
    private String description; // 뜻 (예: 공기 유량 센서 회로 이상)

    // Getter & Setter
    // 🟢
    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
}