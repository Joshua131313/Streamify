import { useSearchParams } from "react-router-dom";
import { Container } from "../../components/layout/Container/Container";
import { EpisodeCard } from "../../components/ui/MediaCard/EpisodeCard";
import { EpisodeSkeletonCard } from "../../components/ui/MediaCard/SkeletonCards/EpisodeSkeletonCard";
import { useEpisodesContext } from "./EpisodesProvider";

export const EpisodesList = () => {
    const { episodes, isLoading, search, direction, currentEpisode } = useEpisodesContext();
    // const episode = 
    const filtered = episodes
        ?.filter(
            (e) =>
                e.episode_number.toString() === search ||
                e.name.toLowerCase().includes(search.toLowerCase())
        )
        .sort((a, b) =>
            direction === "desc"
                ? b.episode_number - a.episode_number
                : a.episode_number - b.episode_number
        );
    const skeletonRow = Array.from({ length: 5 }).map((_, i) => (
          <EpisodeSkeletonCard key={i} />
    )) 
    const episodesRow = filtered.map((ep) => (
        <EpisodeCard key={ep.id} episode={ep} isSelected={currentEpisode === ep.episode_number}/>
    ))

  return (
    <Container className="episodes-list" styled>
        {
            isLoading ? 
            skeletonRow :
            !filtered.length ?
            <div className="no-episodes-found">No episodes found</div> :
            episodesRow
        }
    </Container>
  );
};
