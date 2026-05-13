import { useWatchHistoryContext } from "../../../../context/WatchHistoryContext";

import MediaRail from "../../../media/MediaRail/MediaRail";

import { AppSwiper } from "../../../ui/AppSwiper/AppSwiper";

import { ContinueWatchingCard }
from "../../../ui/MediaCard/ContinueWatchingCard";

import { MediaSkeletonCard }
from "../../../ui/MediaCard/SkeletonCards/MediaSkeletonCard";

import { Title } from "../../../ui/Title/Title";

import { providers }
from "../../../../data/providers";

import { getMainGenres }
from "../../../../data/TMDBGenres";

import "./RailsContainer.css";

export const RailsContainer = () => {

    const { historyMedia, isLoading } =
        useWatchHistoryContext();

    return (
        <div className="rails-container app-container flex-col">

            {
                historyMedia.length > 0 && (
                    <div className="continue-watching-container">

                        <Title title="Continue watching" />

                        <AppSwiper
                            items={historyMedia}
                            isLoading={isLoading}
                            skeleton={<MediaSkeletonCard />}
                            variant="normal"
                            itemKey={(item) => String(item.id)}
                            renderItem={(m) => (
                                <ContinueWatchingCard media={m} />
                            )}
                        />

                    </div>
                )
            }

            <MediaRail
                title="TOP 10 Today"

                variant="top10"

                buildQuery={() => ({
                    category: "top_10"
                })}
            />

            <MediaRail
                title="For you"

                showMediaTabs

                buildQuery={() => ({
                    category: "for_you"
                })}
            />

            <MediaRail
                title="Trending Today"

                showMediaTabs

                buildQuery={() => ({
                    category: "trending"
                })}
            />

            <MediaRail
                title="Only on"

                showMediaTabs

                selectOptions={
                    providers.map((p) => ({
                        label: p.name,
                        value: p.provider
                    }))
                }

                defaultSelect="netflix"

                buildQuery={({ selectedValue }) => ({
                    category: "provider",
                    provider: selectedValue as any
                })}
            />

            <MediaRail
                title="Top rated"

                showMediaTabs

                buildQuery={() => ({
                    category: "top_rated"
                })}
            />

            <MediaRail
                title=""
                
                className="genres-rail"
                showMediaTabs

                selectOptions={getMainGenres("movie")}

                defaultSelect="16"

                buildQuery={({ selectedValue }) => ({
                    category: "by_genre",
                    genreId: selectedValue
                })}
            />

        </div>
    );
};