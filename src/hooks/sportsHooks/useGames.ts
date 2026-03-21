import { useEffect, useState } from "react"
import { type IGames } from "../../types/sports"

export const filterGames = (games: IGames, search: string): IGames => {
    return games.filter(game => {
        const searchNormalized = search.toLocaleLowerCase().trim();
        const awayTeamNormalized = game.awayTeam.name.toLocaleLowerCase();
        const homeTeamNormalized = game.homeTeam.name.toLocaleLowerCase();
        const gameNormalized = game.game.toLocaleLowerCase();
        if (
            awayTeamNormalized.includes(searchNormalized) ||
            homeTeamNormalized.includes(searchNormalized) ||
            gameNormalized.includes(searchNormalized)
        ) {
            return game;
        }
    })
}

export const useGames = () => {
    const [games, setGames] = useState<IGames>([]);
    const [search, setSearch] = useState("");
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchGames = async () => {
            try {
                const API_URL = import.meta.env.VITE_API_URL || "";
                const response = await fetch(`${API_URL}/api/scrape`);
                if (!response.ok) {
                    throw new Error("Failed to get games");
                }
                const data: IGames = await response.json();
                setGames(data)
            }
            catch (err: any) {
                setError(err.message);
            }
            finally {
                setLoading(false);
            }
        }
        fetchGames();
    }, [])

    return {
        games,
        loading,
        error,
        search,
        setSearch
    }

}

