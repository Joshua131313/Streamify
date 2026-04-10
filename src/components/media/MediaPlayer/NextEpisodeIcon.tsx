import { FaChevronRight } from "react-icons/fa"
import { EpisodesProvider } from "../../../pages/Show/EpisodesProvider"
import { Icon } from "../../ui/Icon/Icon"
import { useEpisodeCount } from "../../../hooks/mediaHooks/showHooks/useEpisodeCount"
import { useParams, useSearchParams } from "react-router-dom"
import { Button } from "../../ui/Button/Button"


export const NextEpisodeIcon = () => {
    const { showId } = useParams<{showId: string}>();
    const [searchParams, setSearchParams] = useSearchParams();
    const season = Number(searchParams.get("season"));
    const episode = Number(searchParams.get("episode"));
    const { data : episodeCount } = useEpisodeCount({
        showId: Number(showId),
        seasonNumber: season,
    });
    const setNextEpisode = () => {
        if(!episodeCount) return;
        
        const next = new URLSearchParams(searchParams);

        if(episode === episodeCount) {
            next.set("season", String(season + 1));
            next.set("episode", "1");
        }
        else {
            next.set("episode", String(episode + 1));
        }
        setSearchParams(next);
    }

    return (
        <Button 
            className="next-episode-icon player-control-icon" 
            onClick={setNextEpisode}
        >Next episode</Button>
    )
}