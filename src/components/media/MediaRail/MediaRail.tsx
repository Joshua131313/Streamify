import React from "react";
import type {
    TLabelValue,
    TMediaTypeSelect,
    TStreamCategories,
    TStreamProviders
} from "../../../types/tmdb";
import "./MediaRail.css"

import type { TSwiperVariant } from "../../ui/AppSwiper/AppSwiper";

import { MediaRailProvider } from "./MediaRailContext";
import { MediaRailHeader } from "./MediaRailHeader";
import { MediaRailSwiper } from "./MediaRailSwiper";

export type TMediaRailQuery = {
    category: TStreamCategories;
    genreId?: string;
    provider?: TStreamProviders;
};

interface Props {
    title: string;

    variant?: TSwiperVariant;

    showMediaTabs?: boolean;

    selectOptions?: TLabelValue[];
    defaultSelect?: string;
    className?: string;

    buildQuery: (params: {
        mediaType: TMediaTypeSelect;
        selectedValue?: string;
    }) => TMediaRailQuery;
}

const MediaRail = ({
    title,
    variant = "normal",
    showMediaTabs = false,
    selectOptions,
    defaultSelect,
    className,
    buildQuery
}: Props) => {
    return (
        <MediaRailProvider defaultSelect={defaultSelect}>
            <div className={`${className} media-rail flex-col`}>
                <MediaRailHeader
                    title={title}
                    showMediaTabs={showMediaTabs}
                    selectOptions={selectOptions}
                />

                <MediaRailSwiper
                    variant={variant}
                    buildQuery={buildQuery}
                />
            </div>
        </MediaRailProvider>
    );
};

export default React.memo(MediaRail);