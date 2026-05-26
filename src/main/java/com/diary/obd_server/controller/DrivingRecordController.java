package com.diary.obd_server.controller;

import com.diary.obd_server.model.DrivingRecord;
import com.diary.obd_server.repository.DrivingRecordRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/driving")
public class DrivingRecordController {

    @Autowired
    private DrivingRecordRepository drivingRepository;

    // 1. 주행 기록 저장 API (기존)
    @PostMapping("/save")
    public ResponseEntity<?> saveDrivingRecord(@RequestBody DrivingRecord record) {
        drivingRepository.save(record);
        return ResponseEntity.ok(Map.of("status", "success", "message", "주행 상세 기록이 클라우드 DB에 무사히 저장되었습니다."));
    }

    // 💡 2. [신규] 과거 주행 기록 목록 조회 API
    @GetMapping("/history")
    public ResponseEntity<?> getDrivingHistory(@RequestParam String email) {
        // 이메일을 기준으로 최신순(역순)으로 모든 기록을 찾아옵니다.
        List<DrivingRecord> history = drivingRepository.findByUserEmailOrderByIdDesc(email);
        return ResponseEntity.ok(history);
    }

    // 💡 3. [신규] 주행 기록 삭제 API
    @DeleteMapping("/delete/{id}")
    public ResponseEntity<?> deleteRecord(@PathVariable Long id) {
        drivingRepository.deleteById(id);
        return ResponseEntity.ok(Map.of("status", "success", "message", "삭제되었습니다."));
    }
}