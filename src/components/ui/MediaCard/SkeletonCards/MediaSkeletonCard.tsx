import "../MediaCard.css";
import "./Skeletons.css"

export const MediaSkeletonCard = (
    props: { className?: string }
) => {

    return (

        <div
            className={`${props.className || ""} media-skeleton-card`}
        >

            <div className="skeleton-img"></div>

            <div className="skeleton-content">

                <div className="skeleton-line skeleton-title"></div>

                <div className="skeleton-details">

                    <div className="skeleton-line skeleton-small skeleton-rating"></div>

                    <div className="skeleton-line skeleton-small skeleton-year"></div>

                    <div className="skeleton-line skeleton-small skeleton-type"></div>

                </div>

            </div>

        </div>
    );
};