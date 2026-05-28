package com.diary.obd_server.controller;

import com.diary.obd_server.model.User;
import com.diary.obd_server.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api")
public class AuthController {

    @Autowired
    private UserRepository userRepository;

    // [기존] 로그인 기능 (사용자 정보도 같이 넘겨주도록 수정)
    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody Map<String, String> loginData) {
        String email = loginData.get("email");
        String password = loginData.get("password");

        Optional<User> userOptional = userRepository.findByEmail(email);

        if (userOptional.isPresent() && userOptional.get().getPassword().equals(password)) {
            User user = userOptional.get();
            Map<String, Object> response = new HashMap<>();
            response.put("status", "success");
            response.put("message", "로그인 성공");
            response.put("name", user.getName());
            response.put("carType", user.getCarType());
            return ResponseEntity.ok(response);
        } else {
            return ResponseEntity.status(401).body(Map.of("status", "error", "message", "정보가 일치하지 않습니다"));
        }
    }

    // [신규] 회원가입 기능 추가
    @PostMapping("/signup")
    public ResponseEntity<?> signup(@RequestBody User newUser) {
        // 이메일 중복 검사
        if (userRepository.findByEmail(newUser.getEmail()).isPresent()) {
            return ResponseEntity.status(400).body(Map.of("status", "error", "message", "이미 가입된 이메일입니다."));
        }

        // 새 유저 DB에 저장
        userRepository.save(newUser);
        return ResponseEntity.ok(Map.of("status", "success", "message", "회원가입이 완료되었습니다!"));
    }
}