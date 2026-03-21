export type IGame = {
  date: string;
  game: string;
  stream: string;
  status: "live" | "not_started";
  homeTeam: {
    name: string;
    logo: string;
  };
  awayTeam: {
    name: string;
    logo: string;
  };
};


export type IGames = IGame[];