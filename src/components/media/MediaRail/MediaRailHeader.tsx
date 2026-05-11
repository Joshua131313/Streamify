// MediaRailHeader.tsx

import type { TLabelValue } from "../../../types/tmdb";

import { AccentLine } from "../../ui/AccentLine/AccentLine";
import { StyledSelect } from "../../ui/StyledSelect/StyledSelect";

import { useMediaRail } from "./MediaRailContext";
import { MediaTypeTabs } from "./MediaTypeTabs";

interface Props {
    title: string;

    selectOptions?: TLabelValue[];

    showMediaTabs?: boolean;
}

export const MediaRailHeader = ({
    title,
    selectOptions,
    showMediaTabs
}: Props) => {
    const {
        selectedValue,
        setSelectedValue
    } = useMediaRail();

    const selectedOption =
        selectOptions?.find(
            x => x.value === selectedValue
        ) ?? null;

    return (
        <div className="rail-header flex-row sb">
            <div className="flex-row rail-title-group">
                <AccentLine />

                <div className="flex-row rail-title-content">
                    <h2>{title}</h2>

                    {
                        selectOptions && (
                            <StyledSelect<TLabelValue, false>
                                options={selectOptions}
                                value={selectedOption}
                                onChange={(v) => {
                                    if (!v) return;
                                    setSelectedValue(v.value);
                                }}
                                className="rail-select"
                                isSearchable={false}
                            />
                        )
                    }
                </div>
            </div>

            {
                showMediaTabs && (
                    <MediaTypeTabs />
                )
            }
        </div>
    );
};