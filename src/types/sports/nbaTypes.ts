export type NBAGameStatus =
  | "SCHEDULED"
  | "PRE"
  | "LIVE"
  | "HALFTIME"
  | "FINAL";

export interface NBATeam {
  id: string;
  name: string;
  abbreviation: string;
  logo: string;

  score: number;

  record?: string;

  // optional stats later
  fouls?: number;
  timeouts?: number;
}

export interface NBAPeriod {
  current: number;        // quarter (1–4)
  type: "REG" | "OT";
  isHalftime: boolean;
}

export interface NBABroadcast {
  market: string;
  network: string;
}

export interface INBAGame {
  // 🔑 core
  id: string;

  // ⏱ time
  date: string;

  // 📍 venue
  venue?: {
    name: string;
    city?: string;
    state?: string;
  };

  // 📊 status
  status: NBAGameStatus;
  clock?: string;

  // 🏀 teams
  homeTeam: NBATeam;
  awayTeam: NBATeam;

  // ⏱ game flow
  period?: NBAPeriod;

  // 📺 broadcast
  broadcasts?: NBABroadcast[];

  // 🔗 link
  gameLink?: string;

}