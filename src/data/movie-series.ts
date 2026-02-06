export interface TMovieSeriesID {
    name: string;
    id: number;
    featured?: boolean;
    genres: number[]
}

export const moviesSeries: TMovieSeriesID[] = [
  { name: "Harry Potter", id: 1241, featured: true, genres: [12, 14] },
  { name: "The Lord of the Rings", id: 119, featured: true, genres: [12, 14, 28] },
  { name: "The Hobbit", id: 121938, genres: [12, 14] },
  { name: "Star Wars", id: 10, featured: true, genres: [12, 28, 878] },
  { name: "Pirates of the Caribbean", id: 295, genres: [12, 28, 14] },
  { name: "The Dark Knight Trilogy", id: 263, genres: [28, 18, 53] },
  { name: "Jurassic Park", id: 328, featured: true, genres: [12, 28, 878] },
  { name: "Fast & Furious", id: 9485, genres: [28, 53] },
  { name: "The Matrix", id: 2344, genres: [28, 878] },
  { name: "Indiana Jones", id: 84, genres: [12, 28] },
  { name: "Mission: Impossible", id: 87359, genres: [28, 53] },
  { name: "Transformers", id: 8650, genres: [28, 878] },
  { name: "The Hunger Games", id: 131635, featured: true, genres: [28, 878, 12] },
  { name: "James Bond", id: 645, genres: [28, 12, 53] },
  { name: "The Avengers", id: 86311, genres: [28, 878, 12] },
  { name: "X-Men", id: 748, genres: [28, 878] },
  { name: "Spider-Man (Raimi)", id: 556, genres: [28, 12] },
  { name: "Spider-Man (Amazing)", id: 125574, genres: [28, 12] },
  { name: "Spider-Man (MCU)", id: 531241, genres: [28, 12, 878] },
  { name: "Batman (1989–1997)", id: 120794, genres: [28, 53] },
];
