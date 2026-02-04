export interface TMovieSeriesID {
    name: string;
    id: number;
    featured?: boolean;
}

export const moviesSeries : TMovieSeriesID[] = [
  { name: "Harry Potter", id: 1241, featured: true },
  { name: "The Lord of the Rings", id: 119, featured: true },
  { name: "The Hobbit", id: 121938 },
  { name: "Star Wars", id: 10, featured: true },
  { name: "Pirates of the Caribbean", id: 295 },
  { name: "The Dark Knight Trilogy", id: 263 },
  { name: "Jurassic Park", id: 328, featured: true },
  { name: "Fast & Furious", id: 9485 },
  { name: "The Matrix", id: 2344 },
  { name: "Indiana Jones", id: 84 },
  { name: "Mission: Impossible", id: 87359 },
  { name: "Transformers", id: 8650 },
  { name: "The Hunger Games", id: 131635, featured: true },
  { name: "James Bond", id: 645 },
  { name: "The Avengers", id: 86311 },
  { name: "X-Men", id: 748 },
  { name: "Spider-Man (Raimi)", id: 556 },
  { name: "Spider-Man (Amazing)", id: 125574 },
  { name: "Spider-Man (MCU)", id: 531241 },
  { name: "Batman (1989–1997)", id: 120794 },
];
