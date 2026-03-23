export interface TMovieSeriesID {
    name: string;
    id: number;
    featured?: boolean;
    genres: number[];
    backdrop?: string;
}

export const moviesSeries: TMovieSeriesID[] = [
  { name: "Harry Potter", id: 1241, featured: true, genres: [12, 14], backdrop: "/images/harry-potter.jpg" },
  { name: "The Lord of the Rings", id: 119, featured: true, genres: [12, 14, 28], backdrop: "/images/lord-of-the-rings.jpg" },
  { name: "The Hobbit", id: 121938, genres: [12, 14], backdrop: "/images/hobbit.jpg" },
  { name: "Star Wars", id: 10, featured: true, genres: [12, 28, 878], backdrop: "/images/star-wars.jpg" },
  { name: "Pirates of the Caribbean", id: 295, genres: [12, 28, 14], backdrop: "/images/pirates.jpg" },
  { name: "The Dark Knight Trilogy", id: 263, genres: [28, 18, 53], backdrop: "/images/dark-knight.jpg" },
  { name: "Jurassic Park", id: 328, featured: true, genres: [12, 28, 878], backdrop: "/images/jurassic-park.jpg" },
  { name: "Fast & Furious", id: 9485, genres: [28, 53], backdrop: "/images/fast-furious.jpg" },
  { name: "The Matrix", id: 2344, genres: [28, 878], backdrop: "/images/matrix.jpg" },
  { name: "Indiana Jones", id: 84, genres: [12, 28], backdrop: "/images/indiana-jones.jpg" },
  { name: "Mission: Impossible", id: 87359, genres: [28, 53], backdrop: "/images/mission-impossible.jpg" },
  { name: "Transformers", id: 8650, genres: [28, 878], backdrop: "/images/transformers.jpg" },
  { name: "The Hunger Games", id: 131635, featured: true, genres: [28, 878, 12], backdrop: "/images/hunger-games.jpg" },
  { name: "James Bond", id: 645, genres: [28, 12, 53], backdrop: "/images/james-bond.jpg" },
  { name: "The Avengers", id: 86311, genres: [28, 878, 12], backdrop: "/images/avengers.jpg" },
  { name: "X-Men", id: 748, genres: [28, 878], backdrop: "/images/x-men.jpg" },
  { name: "Spider-Man (MCU)", id: 531241, genres: [28, 12, 878], backdrop: "/images/spiderman-mcu.jpg" },
];