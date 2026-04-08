import fs from "fs";
import https from "https";
import path from "path";
import sharp from "sharp";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const images = [
  { name: "harry-potter", url: "https://wallpapercave.com/wp/wp12425258.jpg" },
  { name: "lord-of-the-rings", url: "https://wallpapercave.com/wp/wp15482968.jpg" },
  { name: "hobbit", url: "https://wallpapercave.com/wp/euBO8wi.jpg" },
  { name: "star-wars", url: "https://wallpapercave.com/wp/wp11315982.jpg" },
  { name: "pirates", url: "https://wallpapercave.com/wp/wp8407051.jpg" },
  { name: "dark-knight", url: "https://wallpapercave.com/wp/wp4949190.jpg" },
  { name: "jurassic-park", url: "https://wallpapercave.com/wp/wp6758704.png" },
  { name: "fast-furious", url: "https://wallpapercave.com/wp/wp9702306.jpg" },
  { name: "matrix", url: "https://wallpapercave.com/wp/wp2726662.jpg" },
  { name: "indiana-jones", url: "https://wallpapercave.com/wp/wp14816639.webp" },
  { name: "mission-impossible", url: "https://wallpapercave.com/wp/wp16171234.jpg" },
  { name: "transformers", url: "https://wallpapercave.com/wp/wp13134384.jpg" },
  { name: "hunger-games", url: "https://wallpapercave.com/wp/wp6877510.jpg" },
  { name: "james-bond", url: "https://wallpapercave.com/wp/wp13214928.jpg" },
  { name: "avengers", url: "https://wallpapercave.com/wp/wp14407243.jpg" },
  { name: "x-men", url: "https://wallpapercave.com/wp/wp8943117.jpg" },
  { name: "spiderman-mcu", url: "https://wallpapercave.com/wp/wp7275111.jpg" },
];

const folder = path.join(__dirname, "public/images");

if (!fs.existsSync(folder)) {
  fs.mkdirSync(folder, { recursive: true });
}

const downloadAndCompress = (name, url) => {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      const chunks = [];

      res.on("data", (chunk) => chunks.push(chunk));

      res.on("end", async () => {
        try {
          const buffer = Buffer.concat(chunks);

          const filePath = path.join(folder, `${name}.jpg`);

          await sharp(buffer)
            .resize({ width: 1920 }) 
            .jpeg({ quality: 75 })   
            .toFile(filePath);

          console.log(`Optimized: ${name}.jpg`);
          resolve();
        } catch (err) {
          console.error(`Error processing ${name}:`, err);
          reject(err);
        }
      });
    }).on("error", reject);
  });
};

(async () => {
  for (const img of images) {
    await downloadAndCompress(img.name, img.url);
  }
})();