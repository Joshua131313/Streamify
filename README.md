# 🎬 Streamify

Streamify is a modern, full-featured web application that allows users to discover, watch, and manage movies, TV shows, and live sports — all in one place. It combines media browsing, streaming, and real-time sports viewing into a seamless and interactive experience.

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
