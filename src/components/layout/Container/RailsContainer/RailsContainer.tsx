import { useWatchHistoryContext } from "../../../../context/WatchHistoryContext"
import MediaRail from "../../../media/MediaRail/MediaRail"
import { AppSwiper } from "../../../ui/AppSwiper/AppSwiper"
import { ContinueWatchingCard } from "../../../ui/MediaCard/ContinueWatchingCard"
import { SwiperSkeletonCard } from "../../../ui/MediaCard/SkeletonCards/MediaSkeletonCard"
import { Title } from "../../../ui/Title/Title"
import "./RailsContainer.css"

export const RailsContainer = () => {

    const { historyMedia } = useWatchHistoryContext();

    return (
        <div className="rails-container app-container flex-col">
            {
                historyMedia.length > 0 &&
                <div className="continue-watching-container">
                    <Title title="Continue watching" />
                    <AppSwiper
                        items={historyMedia}
                        isLoading={false}
                        skeleton={<SwiperSkeletonCard />}
                        variant={"normal"}
                        itemKey={(item) => String(item.id)}
                        renderItem={(m, i) =>
                            <ContinueWatchingCard media={m} />
                        }
                    />
                </div>
            }
            <MediaRail
                title="Top 10"
                variant="top10"
                category="top_10"
                mediaType="movie"
            />
            <MediaRail
                category="for_you"
                mediaType="movie"
                title="For you"
            />
            <MediaRail
                category="trending"
                mediaType="movie"
                title="Trending Today"
            />
            <MediaRail
                category="provider"
                mediaType="movie"
                title="Movies on"
            />
            <MediaRail
                category="top_rated"
                mediaType="movie"
                title="Top rated"
            />
            <MediaRail
                category="by_genre"
                mediaType="movie"
                title="Genres"
            />
        </div>
    )
}