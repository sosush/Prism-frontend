package com.prism.security_core.service;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Base64;
import java.util.Comparator;
import java.util.stream.Stream;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

@Service
public class VideoProcessingService {

    // Folders to store data
    private static final String UPLOAD_DIR = "Video/";
    private static final String FRAMES_DIR = "Video/frames/";
    private static final String JSON_DIR = "Video/json/";

    public String processVideo(MultipartFile file, String wallet, String screenColor) throws Exception {
        // 1. Create Directories if they don't exist
        new File(UPLOAD_DIR).mkdirs();
        new File(FRAMES_DIR).mkdirs();
        new File(JSON_DIR).mkdirs();

        // 2. Save the Raw Video File
        String fileName = System.currentTimeMillis() + "_" + file.getOriginalFilename();
        Path videoPath = Paths.get(UPLOAD_DIR + fileName);
        Files.write(videoPath, file.getBytes());

        // 3. Extract Frames using FFmpeg
        String framePattern = FRAMES_DIR + "frame_%03d.jpg";

        // --- FIX STARTS HERE ---
        // TODO: CHANGE THIS PATH to exactly where your ffmpeg.exe is located!
        // Example: "C:\\Users\\Sumit\\ffmpeg\\bin\\ffmpeg.exe"
        // Note: Use double backslashes "\\" for Windows paths.
        String ffmpegPath = "C:\\ffmpeg\\bin\\ffmpeg.exe";

        ProcessBuilder pb = new ProcessBuilder(
                ffmpegPath, // <--- Using the full path here
                "-i", videoPath.toString(),
                "-vf", "scale=640:-1", // ENHANCE: Resize for consistent ML input
                "-r", "5", // Extract 5 frames per second
                "-q:v", "2", // High Quality JPEG
                framePattern);
        // --- FIX ENDS HERE ---

        pb.redirectErrorStream(true);
        Process process = pb.start();
        process.waitFor(); // Wait for extraction to finish

        // 4. Generate JSON from the extracted frames
        return generateJsonFromFrames(wallet, screenColor, fileName);
    }

    private String generateJsonFromFrames(String wallet, String screenColor, String videoName) throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        ArrayNode framesArray = mapper.createArrayNode();

        // Walk through the frames folder
        try (Stream<Path> paths = Files.walk(Paths.get(FRAMES_DIR))) {
            paths.filter(Files::isRegularFile)
                    .filter(p -> p.toString().endsWith(".jpg"))
                    .sorted(Comparator.comparing(Path::toString))
                    .forEach(path -> {
                        try {
                            // Convert Image to Base64
                            byte[] fileContent = Files.readAllBytes(path);
                            String base64 = Base64.getEncoder().encodeToString(fileContent);

                            // Create the JSON Object per frame
                            ObjectNode frameNode = mapper.createObjectNode();
                            frameNode.put("image", base64);
                            frameNode.put("screenColor", screenColor);
                            frameNode.put("wallet", wallet);

                            framesArray.add(frameNode);

                            // Clean up: Delete frame image after adding to JSON
                            Files.delete(path);

                        } catch (IOException e) {
                            e.printStackTrace();
                        }
                    });
        }

        // Write the final JSON file
        String jsonFileName = JSON_DIR + videoName + "_data.json";
        mapper.writeValue(new File(jsonFileName), framesArray);

        return jsonFileName;
    }
}