package com.prism.security_core.auth;



import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.prism.security_core.service.VideoProcessingService;

@RestController
@RequestMapping("/api/video")
@CrossOrigin(origins = "*") // Allows your HTML frontend to talk to this backend
public class VideoUploadController {

    @Autowired
    private VideoProcessingService videoService;

    @PostMapping("/upload")
    public ResponseEntity<String> uploadVideo(
            @RequestParam("video") MultipartFile video,
            @RequestParam("wallet") String walletAddress,
            @RequestParam("screenColor") String screenColor) {
        try {
            String jsonPath = videoService.processVideo(video, walletAddress, screenColor);
            return ResponseEntity.ok("Video Uploaded & Enhanced. JSON Data ready at: " + jsonPath);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error: " + e.getMessage());
        }
    }
}
