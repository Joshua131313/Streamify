import { useEffect, useState } from "react"
import { type IGames } from "../../types/sports"


export const useGames = () => {
    const [games, setGames] = useState<IGames>([]); 
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchGames = async () => {
            try {
                const API_URL = import.meta.env.VITE_API_URL || "";
                const response = await fetch(`${API_URL}/api/scrape`);
                if(!response.ok) {
                    throw new Error("Failed to get games");
                }
                const data = await response.json();
                console.log(data)
                setGames(data);
            }
            catch (err : any) {
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
        error
    }

}

