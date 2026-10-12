import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { createPortal } from "react-dom";
import { FaCheck, FaChevronDown, FaServer } from "react-icons/fa";
import "./PlayerSelect.css";

interface Props {
    label: string;
    value: string;
    options: { value: string; label: string }[];
    onChange: (value: string) => void;
}

export const PlayerSelect = ({ label, value, options, onChange }: Props) => {
    const id = useId();
    const trigger = useRef<HTMLButtonElement>(null);
    const menu = useRef<HTMLDivElement>(null);
    const [open, setOpen] = useState(false);
    const [active, setActive] = useState(0);
    const [position, setPosition] = useState({ left: 0, top: 0, width: 260, maxHeight: 320 });
    const selected = options.find(option => option.value === value);
    const search = useRef({ text: "", time: 0 });

    const openMenu = () => {
        if (!options.length || !trigger.current) return;
        const rect = trigger.current.getBoundingClientRect();
        const width = Math.min(Math.max(rect.width, 240), window.innerWidth - 24);
        const below = window.innerHeight - rect.bottom - 20;
        const above = rect.top - 20;
        const upward = below < Math.min(options.length * 44 + 48, 320) && above > below;
        const maxHeight = Math.max(60, Math.min(320, upward ? above : below));
        const height = Math.min(options.length * 44 + 48, maxHeight);
        setPosition({
            left: Math.max(12, Math.min(rect.left, window.innerWidth - width - 12)),
            top: upward ? Math.max(12, rect.top - height - 8) : rect.bottom + 8,
            width,
            maxHeight,
        });
        setActive(Math.max(0, options.findIndex(option => option.value === value)));
        setOpen(true);
    };

    const choose = (index: number) => {
        const option = options[index];
        if (!option) return;
        onChange(option.value);
        setOpen(false);
        trigger.current?.focus();
    };

    useEffect(() => {
        if (!open) return;
        const close = () => setOpen(false);
        const outside = (event: PointerEvent) => {
            if (!trigger.current?.contains(event.target as Node) && !menu.current?.contains(event.target as Node)) close();
        };
        const scroll = (event: Event) => {
            if (!menu.current?.contains(event.target as Node)) close();
        };
        document.addEventListener("pointerdown", outside);
        document.addEventListener("scroll", scroll, true);
        window.addEventListener("resize", close);
        window.addEventListener("blur", close);
        document.addEventListener("fullscreenchange", close);
        return () => {
            document.removeEventListener("pointerdown", outside);
            document.removeEventListener("scroll", scroll, true);
            window.removeEventListener("resize", close);
            window.removeEventListener("blur", close);
            document.removeEventListener("fullscreenchange", close);
        };
    }, [open]);

    useEffect(() => {
        if (open) menu.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" });
    }, [active, open]);

    const handleKey = (event: KeyboardEvent<HTMLButtonElement>) => {
        if (event.key === "Tab") { setOpen(false); return; }
        if (event.key === "Escape") { event.preventDefault(); setOpen(false); return; }
        if (["ArrowDown", "ArrowUp", "Home", "End", "Enter", " "].includes(event.key)) {
            event.preventDefault();
            if (!open) { openMenu(); return; }
            if (event.key === "Enter" || event.key === " ") { choose(active); return; }
            setActive(index => event.key === "Home" ? 0 : event.key === "End" ? options.length - 1 :
                (index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length);
        } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
            const now = Date.now();
            search.current = { text: (now - search.current.time < 700 ? search.current.text : "") + event.key.toLowerCase(), time: now };
            if (!open) openMenu();
            const index = options.findIndex(option => option.label.toLowerCase().startsWith(search.current.text));
            if (index >= 0) setActive(index);
        }
    };

    return (
        <>
            <button ref={trigger} type="button" role="combobox" className="player-select" aria-label={label}
                aria-haspopup="listbox" aria-expanded={open} aria-controls={open ? id : undefined}
                aria-activedescendant={open && options[active] ? `${id}-${active}` : undefined}
                disabled={!options.length} onClick={() => open ? setOpen(false) : openMenu()}
                onKeyDown={handleKey} onBlur={() => setOpen(false)}>
                <FaServer className="player-select-icon" aria-hidden="true" />
                <span className="player-select-field">
                    <span className="player-select-label">{label}</span>
                    <span className="player-select-value">{selected?.label ?? "No streams available"}</span>
                </span>
                <FaChevronDown className="player-select-chevron" aria-hidden="true" />
            </button>
            {open && createPortal(
                <div ref={menu} className="player-select-menu" style={position} onPointerDown={event => event.preventDefault()}>
                    <div className="player-select-heading">Choose {label.toLowerCase()}</div>
                    <div id={id} role="listbox" aria-label={label}>
                        {options.map((option, index) => (
                            <div key={option.value} id={`${id}-${index}`} role="option" aria-selected={option.value === value}
                                data-index={index} className={`player-select-option${index === active ? " is-active" : ""}`}
                                onPointerMove={() => setActive(index)} onClick={() => choose(index)}>
                                <span>{option.label}</span>
                                {option.value === value && <FaCheck aria-hidden="true" />}
                            </div>
                        ))}
                    </div>
                </div>, document.fullscreenElement ?? document.body
            )}
        </>
    );
};
