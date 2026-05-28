package com.diary.obd_server.controller;

import com.diary.obd_server.dto.DriveDto;
import com.diary.obd_server.service.DriveService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/drive")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class DriveController {

    private final DriveService driveService;

    // POST /api/drive/predict
    @PostMapping("/predict")
    public ResponseEntity<DriveDto.PredictResponse> predict(
            @RequestBody DriveDto.PredictRequest request) {
        DriveDto.PredictResponse response = driveService.predict(request);
        return ResponseEntity.ok(response);
    }

    // GET /api/drive/records
    @GetMapping("/records")
    public ResponseEntity<List<DriveDto.RecordResponse>> getAllRecords() {
        return ResponseEntity.ok(driveService.getAllRecords());
    }

    // GET /api/drive/records/recent
    @GetMapping("/records/recent")
    public ResponseEntity<List<DriveDto.RecordResponse>> getRecentRecords() {
        return ResponseEntity.ok(driveService.getRecentRecords());
    }
}