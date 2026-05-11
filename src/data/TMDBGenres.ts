import type { IconType } from "react-icons";
import type { TLabelValue, TMediaType } from "../types/tmdb";
export type TGenre = {
  label: string;
  value: string;
  media: TMediaType[]; 
  icon?: React.ElementType;
};
import {
    FaMask,
    FaLaughSquint,
    FaUserSecret,
    FaCamera,
    FaTheaterMasks,
    FaChild,
    FaSearch,
    FaHatCowboy,

    FaBomb,
    FaMapMarkedAlt,
    FaDragon,
    FaLandmark,
    FaGhost,
    FaMusic,
    FaHeart,
    FaRocket,
    FaTv,
    FaSkullCrossbones,
    FaShieldAlt,

    FaFistRaised,
    FaBaby,
    FaNewspaper,
    FaVideo,
    FaRobot,
    FaSoap,
    FaMicrophone,
    FaFlag
} from "react-icons/fa";

export const TMDB_GENRES: TGenre[] = [

    // Shared

    {
        label: "Animation",
        value: "16",
        media: ["movie", "tv"],
        icon: FaMask
    },

    {
        label: "Comedy",
        value: "35",
        media: ["movie", "tv"],
        icon: FaLaughSquint
    },

    {
        label: "Crime",
        value: "80",
        media: ["movie", "tv"],
        icon: FaUserSecret
    },

    {
        label: "Documentary",
        value: "99",
        media: ["movie", "tv"],
        icon: FaCamera
    },

    {
        label: "Drama",
        value: "18",
        media: ["movie", "tv"],
        icon: FaTheaterMasks
    },

    {
        label: "Family",
        value: "10751",
        media: ["movie", "tv"],
        icon: FaChild
    },

    {
        label: "Mystery",
        value: "9648",
        media: ["movie", "tv"],
        icon: FaSearch
    },

    {
        label: "Western",
        value: "37",
        media: ["movie", "tv"],
        icon: FaHatCowboy
    },



    // Movie only

    {
        label: "Action",
        value: "28",
        media: ["movie"],
        icon: FaBomb
    },

    {
        label: "Adventure",
        value: "12",
        media: ["movie"],
        icon: FaMapMarkedAlt
    },

    {
        label: "Fantasy",
        value: "14",
        media: ["movie"],
        icon: FaDragon
    },

    {
        label: "History",
        value: "36",
        media: ["movie"],
        icon: FaLandmark
    },

    {
        label: "Horror",
        value: "27",
        media: ["movie"],
        icon: FaGhost
    },

    {
        label: "Music",
        value: "10402",
        media: ["movie"],
        icon: FaMusic
    },

    {
        label: "Romance",
        value: "10749",
        media: ["movie"],
        icon: FaHeart
    },

    {
        label: "Science Fiction",
        value: "878",
        media: ["movie"],
        icon: FaRocket
    },

    {
        label: "TV Movie",
        value: "10770",
        media: ["movie"],
        icon: FaTv
    },

    {
        label: "Thriller",
        value: "53",
        media: ["movie"],
        icon: FaSkullCrossbones
    },

    {
        label: "War",
        value: "10752",
        media: ["movie"],
        icon: FaShieldAlt
    },



    // TV only

    {
        label: "Action & Adventure",
        value: "10759",
        media: ["tv"],
        icon: FaFistRaised
    },

    {
        label: "Kids",
        value: "10762",
        media: ["tv"],
        icon: FaBaby
    },

    {
        label: "News",
        value: "10763",
        media: ["tv"],
        icon: FaNewspaper
    },

    {
        label: "Reality",
        value: "10764",
        media: ["tv"],
        icon: FaVideo
    },

    {
        label: "Sci-Fi & Fantasy",
        value: "10765",
        media: ["tv"],
        icon: FaRobot
    },

    {
        label: "Soap",
        value: "10766",
        media: ["tv"],
        icon: FaSoap
    },

    {
        label: "Talk",
        value: "10767",
        media: ["tv"],
        icon: FaMicrophone
    },

    {
        label: "War & Politics",
        value: "10768",
        media: ["tv"],
        icon: FaFlag
    }
];
export const getGenresByMedia = (media: TMediaType | "all") => {
  if (media === "all") return TMDB_GENRES;

  return TMDB_GENRES.filter(g => g.media.includes(media));
};
export const getMainGenres = (media: TMediaType, limit = 7) =>
  getGenresByMedia(media)
    .slice(0, limit)
    .map(({ label, value }) => ({ label, value }));
