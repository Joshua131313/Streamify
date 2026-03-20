export type IGame = {
  date: string;
  game: string;
  stream: string;
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