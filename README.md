# 🎬 Streamify

Streamify is a modern, full-featured web application that allows users to discover, watch, and manage movies, TV shows, and live sports — all in one place. It combines media browsing, streaming, and real-time sports viewing into a seamless and interactive experience.

---

## 📸 Screenshots

### 🏠 Home Experience

#### 🎥 Hero Carousel (Featured Content)

![Home Carousel](https://github.com/user-attachments/assets/3f50391a-b196-42df-9544-9905af6c2eeb)

#### 🔥 Content Rails (Top 10 & Trending Today)

![Content Rails](https://github.com/user-attachments/assets/3e90e5f3-f8c0-446c-bc4d-369be8859159)
---

### 🎬 Browse Media
![Browse 1](https://github.com/user-attachments/assets/88e50a4e-2f01-44e0-ac32-918e109904b2)
![Player 2](https://github.com/user-attachments/assets/15380137-b717-44ff-949a-d9c57ec292c0)

---

### 🎬 Movie Series Container

![Series 1](https://github.com/user-attachments/assets/63065a1f-f06a-430d-82a8-5e60ae2577ad)

---

### 🎬 Media Details Page
![Details 1](https://github.com/user-attachments/assets/ed3e93ce-4216-4a1c-8ce0-03fd81f7acde)


---

### 🎥 Streaming & Player

![Player 1](https://github.com/user-attachments/assets/65ecd768-97ec-4eed-a8b9-ecb9cdda4883)

---

### 🏀 Sports Section

![Sports 1](https://github.com/user-attachments/assets/bbcea93a-91f6-47fe-9085-030158c04d67)
![Sports 2](https://github.com/user-attachments/assets/1fa2c1ca-3455-4554-8c6a-656fe7e57fa6)
![Sports 3](https://github.com/user-attachments/assets/60634590-f511-4e03-94ca-1e09b70cc63e)

---

### 📺 MultiWatch & Window System

![MultiWatch 1](https://github.com/user-attachments/assets/abf41f5a-573a-4e7f-b395-fe238cf88223)
![MultiWatch 2](https://github.com/user-attachments/assets/ac30750c-fbea-4aad-b91f-a7250babbab9)
![MultiWatch 3](https://github.com/user-attachments/assets/c141271b-0488-4007-b3c0-25a2c26262a2)

---

### 📱 Mobile Screens

<p align="center">
  <img src="https://github.com/user-attachments/assets/47eeee16-5016-48c2-946f-199d12bb6485" alt="UI 1" width="260" />
  <img src="https://github.com/user-attachments/assets/21446930-4358-4cea-93a0-b09ea7927042" alt="UI 2" width="260" />
  <img src="https://github.com/user-attachments/assets/8cc4d085-8b04-4ae5-9e8b-a1a1f8650a6e" alt="UI 3" width="260" />
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/6ca1ff28-6ec1-481d-8be5-7bb730f37f84" alt="UI 4" width="260" />
  <img src="https://github.com/user-attachments/assets/4d85535e-9f95-4770-ab7f-7d5e3af1d17e" alt="UI 5" width="260" />
  <img src="https://github.com/user-attachments/assets/8e7046a6-d499-4ad1-aa25-0d1c74d0838f" alt="UI 6" width="260" />
</p>
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
* Watch movies and shows directly within the app via embedded players (**iframes**)
* Fast and responsive search functionality

---

### 🏀 Sports Streaming

* Watch live and upcoming games from:

  * NBA
  * NHL
  * MLB
* Real-time game data fetched from **ESPN APIs**
* Dynamic game status detection (LIVE, PRE, FINAL)

#### Key Features:

* 🔴 Live game streaming
* 🧠 Smart filtering (Live / Upcoming / Finished)
* ⭐ Follow favorite teams
* 🪟 Watch in a new window
* 📺 MultiWatch mode

---

### 🎮 MultiWatch System

* Watch multiple games simultaneously
* Add/remove games dynamically
* Automatically removes outdated games
* Persisted using local storage

---

### 🔐 Authentication & User Data

* Firebase Authentication:

  * Google login
  * Email/password login
* Firestore database:

  * User profiles
  * Preferences
  * Saved media & watch history

---

### 📺 Streaming System

* Multiple stream providers supported
* Streams embedded via **iframes**
* Dynamic stream selection with fallback support

---

### 📱 Progressive Web App (PWA)

* Installable on desktop and mobile
* Offline support via service workers
* Custom offline screen

---

## 🛠️ Tech Stack

### Frontend

* React.js
* TypeScript
* React Router
* Context API

### Styling

* Custom CSS
* Fully responsive design

### Data & APIs

* **TMDB (The Movie Database)** → movies, TV shows, images
* **ESPN APIs** → sports data

### Backend / Services

* Firebase Authentication
* Firebase Firestore

### Streaming

* Embedded via iframes
* Multiple third-party providers

---

## 🧠 Architecture Highlights

### 🔹 Modular Stream System

```ts
{
  provider: string,
  buildStreamUrl: (params) => string
}
```

* Easily extendable with new providers

---

### 🔹 Window System

* Draggable & resizable windows
* Minimize / fullscreen
* Multi-instance support

---

### 🔹 State Management

* React Context:

  * Auth
  * MultiWatch
  * UI

---

### 🔹 Smart Game Logic

* Based on time (not stale status)
* Ensures only relevant games are shown

---

## 📦 Installation

### 1. Clone

```bash
git clone https://github.com/your-username/streamify.git
cd streamify
```

### 2. Install

```bash
npm install
```

### 3. Run

```bash
npm run dev
```

---

## 📲 PWA Installation

* Chrome → click “Install” in address bar
* Mobile → “Add to Home Screen”

---

## ⚠️ Disclaimer

Streamify does **not host content**.

* Streams are embedded via third-party providers
* App acts as an aggregator/viewer
* Users are responsible for usage

---

## 🔮 Future Improvements

* Automatic stream fallback
* Quality detection
* Notifications for live games
* Better recommendations
* Enhanced offline support

---

## 👨‍💻 Author

Built by **Joshua Bitton**

---

## ⭐ Final Thoughts

Streamify combines:

* 🎬 Media streaming
* 🏀 Live sports
* 🧠 Smart UI/UX

into one powerful, unified entertainment platform.
