import { Container } from "../../components/layout/Container/Container";
import { GenreFilter } from "../../components/ui/filters/GenreFilter";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import { useWatchHistoryContext } from "../../context/WatchHistoryContext";
import { ContinueWatchingCard } from "../../components/ui/MediaCard/ContinueWatchingCard";

const WatchHistory = () => {

    const { historyMedia } = useWatchHistoryContext();
    return (
        <div className="saved-media-page">
            <PageHeader
                title="Continue Watching"
                subTitle=""
                controls={
                    <>
                        <GenreFilter mediaType="all" includeAll />
                    </>
                }
            />
            <Container className="media-grid">
                {
                    // develop custom card for continue watching, clicking will play automatiocally rather than go to the page
                    historyMedia.sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime()).map(m => (
                        <ContinueWatchingCard key={m.id} media={m} />
                    ))
                }
            </Container>
        </div>
    )
}
export default WatchHistory;