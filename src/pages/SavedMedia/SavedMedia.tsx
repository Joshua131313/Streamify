import { useSearchParams } from "react-router-dom";
import { Container } from "../../components/layout/Container/Container";
import { GenreFilter } from "../../components/ui/filters/GenreFilter";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import { useLocalStorage } from "../../hooks/utilHooks/useLocalStorage";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import { MediaCard } from "../../components/ui/MediaCard/MediaCard";
import "./SavedMedia.css"
import { useSavedMediaContext } from "../../context/SavedMediaContext";

const SavedMedia = () => {

    const { savedMedia } = useSavedMediaContext();
    const [searchParams] = useSearchParams();
    const urlGenre = searchParams.get("genre");

    const filteredMedia = urlGenre
        ? savedMedia.filter(m => m.genre_ids?.includes(Number(urlGenre)))
        : savedMedia;

    return (
        <div className="saved-media-page">
            <PageHeader
                title="Saved Media"
                subTitle="Browse all saved for later movies and TV shows"
                controls={
                    <>
                        <GenreFilter mediaType="all" includeAll />
                    </>
                }
            />
            <Container className="media-grid">
                {
                    filteredMedia.map(m => (
                        <MediaCard key={m.id} media={m} />
                    ))
                }
            </Container>
        </div>
    )
}
export default SavedMedia;