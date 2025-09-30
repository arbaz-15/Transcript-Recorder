import dotenv from "dotenv";
dotenv.config();

import express from "express";
import multer from "multer";
import cors from "cors";
import fs from "fs";
import path from "path";
import fetch from "node-fetch"; // if Node >=18, you can just use global fetch

const app = express();
const PORT = process.env.PORT || 3000;
const ASSEMBLY_API_KEY = process.env.ASSEMBLY_API_KEY;

app.use(cors());
app.use(express.json());

// --- Multer setup ---
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = "uploads";
    if (!fs.existsSync(dir)) fs.mkdirSync(dir);
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    cb(null, Date.now() + path.extname(file.originalname));
  }
});

const upload = multer({ storage });

// --- Upload & Transcribe ---
app.post("/upload-audio", upload.single("audio"), async (req, res) => {
  if (!req.file) return res.status(400).json({ message: "No file uploaded ❌" });

  try {
    const fileStream = fs.createReadStream(req.file.path);

    // Upload to AssemblyAI
    const uploadResp = await fetch("https://api.assemblyai.com/v2/upload", {
      method: "POST",
      headers: {
        authorization: ASSEMBLY_API_KEY,
        "transfer-encoding": "chunked"
      },
      body: fileStream
    });

    const uploadData = await uploadResp.json();
    const audioUrl = uploadData.upload_url;

    // Request transcription
    const transcribeResp = await fetch("https://api.assemblyai.com/v2/transcript", {
      method: "POST",
      headers: {
        authorization: ASSEMBLY_API_KEY,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ audio_url: audioUrl })
    });

    const transcriptData = await transcribeResp.json();
    const transcriptId = transcriptData.id;

    // Polling
    let transcriptText = "";
    while (true) {
      const pollResp = await fetch(`https://api.assemblyai.com/v2/transcript/${transcriptId}`, {
        headers: { authorization: ASSEMBLY_API_KEY }
      });
      const pollData = await pollResp.json();

      if (pollData.status === "completed") {
        transcriptText = pollData.text;
        break;
      } else if (pollData.status === "failed") {
        throw new Error("Transcription failed");
      }

      await new Promise(r => setTimeout(r, 3000));
    }

    res.json({
      message: "✅ Upload & transcription successful",
      filePath: req.file.path,
      transcription: transcriptText
    });

  } catch (err) {
    console.error("❌ Error:", err);
    res.status(500).json({ message: "Transcription failed", error: err.message });
  }
});

// --- Start server ---
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server running at http://0.0.0.0:${PORT}`);
});
