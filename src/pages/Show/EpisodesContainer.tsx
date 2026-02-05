import { useEffect, useState } from "react";
import { Container } from "../../components/layout/Container/Container"
import { EpisodeCard } from "../../components/ui/MediaCard/EpisodeCard";
import { useEpisodes } from "../../hooks/mediaHooks/showHooks/useEpisodes";
import type { TMDBShowMedia } from "../../types/TMDBMediaType";
import type { TSeason } from "../../types/TMDBShowType";
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect";
import { Input } from "../../components/ui/Input/Input";
import { FaSearch, FaSortAmountDownAlt, FaSortAmountUpAlt } from "react-icons/fa";
import { Icon } from "../../components/ui/Icon/Icon";
import { EpisodeSkeletonCard } from "../../components/ui/MediaCard/SkeletonCards/EpisodeSkeletonCard";
import { Title } from "../../components/ui/Title/Title";

interface Props {
    show: TMDBShowMedia;
}
type SeasonOption = {
    value: number;
    label: string;
    season: TSeason;
};
export const EpisodesContainer = ({show} : Props) => {
    const [seasonOption, setSeasonOption] = useState<SeasonOption | null>(null);
    const [searchEpisode, setSearchEpisode] = useState<string>("");
    const [direction, setDirection] = useState<"asc" | "desc">("asc");
    const { episodes, isLoading } = useEpisodes({showId: show.id, seasonNumber: seasonOption?.season.season_number ?? 1});

    const seasonOptions: SeasonOption[] = show?.seasons?.map((s) => ({
        value: s.season_number,
        label: s.name,
        season: s
    })) ?? []

    const episodesRow = episodes?.filter(a => a.episode_number.toString() === searchEpisode || (a.name.toLowerCase().includes(searchEpisode.toLowerCase()))).sort((a, b) => {
        if(direction === "desc") return b.episode_number - a.episode_number;
        else return a.episode_number - b.episode_number
    }).map(episode => {
        return (
            <EpisodeCard key={episode.id} episode={episode}/>
        )
    })

    const skeletonRow = Array.from({ length: 5 }).map((_, i) => {
        return (
            <EpisodeSkeletonCard key={i}/>
        )
    })
    useEffect(() => {
    if (!seasonOption && seasonOptions.length) {
        setSeasonOption(seasonOptions[0]);
    }
    }, [seasonOptions, seasonOption]);
    
    return (
        <>
            <div className="layout-container">
                <Title 
                    id="episodes"
                    title="Episodes"
                />
            </div>
            <Container className="season-selector-container" styled>
                <div className="season-selector">
                    <StyledSelect<SeasonOption, false>
                        options={seasonOptions}
                        value={seasonOption}
                        onChange={(opt) => setSeasonOption(opt)}
                        className="select" 
                    />
                    <Input 
                        Icon={FaSearch}
                        placeholder="Search episode..."
                        value={searchEpisode}
                        onChange={(e) => setSearchEpisode(e.target.value)}
                    />
                    <Icon 
                        onClick={() => setDirection(direction === "asc" ? "desc" : "asc")}
                        Icon={direction === "asc" ? FaSortAmountDownAlt : FaSortAmountUpAlt}
                    />
                </div>
            </Container>
            <Container className="episodes-container" styled>
                {
                    episodesRow?.length ?
                    episodesRow :
                    isLoading ? 
                    skeletonRow :
                    <div className="no-episodes-found">
                        No episodes found
                    </div>
                }
            </Container>
     </>
    )
}