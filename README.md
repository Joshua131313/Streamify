# 🎬 Streamify

Streamify is a modern, full-featured web application that allows users to discover, watch, and manage movies, TV shows, and live sports — all in one place. It combines media browsing, streaming, and real-time sports viewing into a seamless and interactive experience.
<img width="3809" height="2094" alt="image" src="https://github.com/user-attachments/assets/3f50391a-b196-42df-9544-9905af6c2eeb" />
<img width="3795" height="2077" alt="image" src="https://github.com/user-attachments/assets/3e90e5f3-f8c0-446c-bc4d-369be8859159" />
<img width="3793" height="2103" alt="image" src="https://github.com/user-attachments/assets/63065a1f-f06a-430d-82a8-5e60ae2577ad" />
<img width="3829" height="2104" alt="image" src="https://github.com/user-attachments/assets/ed3e93ce-4216-4a1c-8ce0-03fd81f7acde" />
<img width="3791" height="2083" alt="image" src="https://github.com/user-attachments/assets/88e50a4e-2f01-44e0-ac32-918e109904b2" />
<img width="3804" height="2081" alt="image" src="https://github.com/user-attachments/assets/15380137-b717-44ff-949a-d9c57ec292c0" />
<img width="3807" height="2100" alt="image" src="https://github.com/user-attachments/assets/65ecd768-97ec-4eed-a8b9-ecb9cdda4883" />
<img width="3797" height="2085" alt="image" src="https://github.com/user-attachments/assets/bbcea93a-91f6-47fe-9085-030158c04d67" />
<img width="3814" height="2090" alt="image" src="https://github.com/user-attachments/assets/1fa2c1ca-3455-4554-8c6a-656fe7e57fa6" />
<img width="3800" height="2091" alt="image" src="https://github.com/user-attachments/assets/60634590-f511-4e03-94ca-1e09b70cc63e" />
<img width="3783" height="2076" alt="image" src="https://github.com/user-attachments/assets/abf41f5a-573a-4e7f-b395-fe238cf88223" />
<img width="3795" height="2096" alt="image" src="https://github.com/user-attachments/assets/ac30750c-fbea-4aad-b91f-a7250babbab9" />
<img width="3836" height="2075" alt="image" src="https://github.com/user-attachments/assets/c141271b-0488-4007-b3c0-25a2c26262a2" />
![500f8baa-d68a-48ff-a0cc-9c77cda2eac4](https://github.com/user-attachments/assets/47eeee16-5016-48c2-946f-199d12bb6485)
![dba14f71-4cdc-4b38-8739-cc9a31d31230](https://github.com/user-attachments/assets/21446930-4358-4cea-93a0-b09ea7927042)
![40b7aac6-77b6-4f42-bd93-544fe60c4ac3](https://github.com/user-attachments/assets/8cc4d085-8b04-4ae5-9e8b-a1a1f8650a6e)
![836a4dab-6e4d-4f20-b5d0-df03258059bf](https://github.com/user-attachments/assets/6ca1ff28-6ec1-481d-8be5-7bb730f37f84)
![47102a88-ea7e-45e6-8083-5bbc22a37dd1](https://github.com/user-attachments/assets/4d85535e-9f95-4770-ab7f-7d5e3af1d17e)
![7cb75a0c-139a-4b24-a4b2-b15ba10b4631](https://github.com/user-attachments/assets/8e7046a6-d499-4ad1-aa25-0d1c74d0838f)

---

## 🚀 Overview

Streamify is designed as a **Progressive Web App (PWA)** that can be used directly in the browser or installed on your device for a native-like experience. It integrates multiple external data sources and streaming providers to deliver a unified entertainment platform.

---

## 🧩 Core Features

### 🎥 Movies & TV Shows

* Browse trending, popular, and upcoming media
* View detailed information including:

  * Posters, backdrops, and metadata
  * Ratings, genres, cast, and descriptions
* Watch movies and shows directly within the app via embedded players (iframes)
* Search functionality for fast discovery

---

### 🏀 Sports Streaming

* Watch live and upcoming games from:

  * NBA
  * NHL
  * MLB
* Real-time game data fetched from ESPN APIs
* Dynamic game status detection (LIVE, PRE, FINAL, etc.)

#### Key Sports Features:

* 🔴 **Live Game Streaming**
* 🧠 **Smart Game Filtering** (Live, Upcoming, Finished)
* ⭐ **Follow Favorite Teams**
* 🪟 **Watch in New Window**
* 📺 **MultiWatch Mode**

  * Watch multiple games simultaneously
  * Manage multiple streams in floating windows

---

### 🎮 MultiWatch System

* Add multiple games to a watchlist
* Open multiple streams simultaneously
* Automatically removes games when they are no longer relevant
* Persistent via local storage

---

### 🔐 Authentication & User Data

* Firebase Authentication:

  * Google login
  * Email/password login
* Firestore database:

  * User profiles
  * Preferences
  * Saved media and watch history

---

### 📺 Streaming System

* Uses multiple stream providers
* Streams are embedded using **iframes**
* Dynamic stream selection:

  * Users can switch between providers
  * Fallback support across providers

---

### 📱 Progressive Web App (PWA)

* Installable on desktop and mobile
* Offline support with service workers
* Custom offline screen when no connection is available

---

## 🛠️ Tech Stack

### Frontend

* React.js
* TypeScript
* React Router
* Context API

### Styling

* Custom CSS (no heavy UI frameworks)
* Responsive design for mobile and desktop

### Data & APIs

* **TMDB (The Movie Database)**
  → Used for movies, TV shows, metadata, images

* **ESPN APIs**
  → Used for live sports data (scores, schedules, teams)

### Backend / Services

* **Firebase Authentication**
* **Firebase Firestore**

### Streaming

* Embedded via **iframes**
* Multiple third-party stream providers

---

## 🧠 Architecture Highlights

### 🔹 Modular Stream System

* Streams are defined as reusable objects:

  ```ts
  {
    provider: string,
    buildStreamUrl: (params) => string
  }
  ```
* Allows flexible addition of new providers

---

### 🔹 Window System

* Custom draggable and resizable windows
* Supports:

  * Minimize
  * Fullscreen
  * Multi-instance viewing

---

### 🔹 State Management

* React Context for global state:

  * Authentication
  * MultiWatch
  * UI state

---

### 🔹 Smart Game Logic

* Game availability is determined dynamically based on:

  * Start time
  * Current time
* Ensures only relevant games are shown

---

## 📦 Installation

### 1. Clone the repository

```bash
git clone https://github.com/your-username/streamify.git
cd streamify
```

### 2. Install dependencies

```bash
npm install
```

### 3. Run the app

```bash
npm run dev
```

---

## 📲 PWA Installation

Streamify can be installed like a native app:

* On Chrome:

  * Click “Install” in the address bar
* On mobile:

  * “Add to Home Screen”

---

## ⚠️ Disclaimer

Streamify does **not host any content**.

* All streams are embedded from third-party providers via iframes
* The app acts as a **viewer/aggregator**
* Users are responsible for how they use the platform

---

## 🔮 Future Improvements

* Automatic stream fallback on failure
* Better stream quality detection
* Notifications for live games
* Enhanced recommendation system
* Improved offline capabilities

---

## 👨‍💻 Author

Built by **Joshua Bitton**

---

## ⭐ Final Thoughts

Streamify combines:

* 🎬 Media streaming
* 🏀 Live sports
* 🧠 Smart UI/UX

into one unified platform, offering a powerful and flexible entertainment experience.
