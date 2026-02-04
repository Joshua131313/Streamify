import { MediaRail } from "../../../media/MediaRail/MediaRail"
import "./RailsContainer.css"

export const RailsContainer = () => {

    return (
        <div className="rails-container app-container flex-col">
            <MediaRail 
                title="Top 10"
                variant="top10"
                category="top10"
                mediaType="movie"
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
                category="byGenre"
                mediaType="movie"
                title="Genres"
            />
        </div>
    )
}