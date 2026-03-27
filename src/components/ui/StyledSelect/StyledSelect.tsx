import Select, {
  type Props as SelectProps,
  type GroupBase,
} from "react-select";
import "./StyledSelect.css"

const styles = {
  control: (base: any, state: any) => ({
    ...base,
    backgroundColor: "var(--bg-primary)",
    borderColor: state.isFocused ? "#dc2626" : "var(--border)",
    boxShadow: "none",
    minHeight: "40px",
    "&:hover": {
      borderColor: "#dc2626",
    },
  }),

  menu: (base: any) => ({
    ...base,
    backgroundColor: "var(--bg-surface)",
    borderRadius: "5px",
    overflow: "hidden",
    zIndex: 50,
  }),

  menuList: (base: any) => ({
    ...base,
    padding: 0,
  }),

  option: (base: any, state: any) => ({
    ...base,
    backgroundColor: state.isSelected
      ? "rgba(220, 38, 38, 0.2)" // 🔴 selected (subtle red)
      : state.isFocused
        ? "var(--bg-surface-hover)" // hover
        : "transparent",
    color: "white",
    cursor: "pointer",
    ":active": {
      backgroundColor: "rgba(220, 38, 38, 0.25)", // click state
    },
  }),

  singleValue: (base: any) => ({
    ...base,
    color: "white",
  }),
  indicatorSeparator: () => ({
    display: "none",
  }),
  placeholder: (base: any) => ({
    ...base,
    color: "var(--text-muted)",
  }),

  input: (base: any) => ({
    ...base,
    color: "white",
  }),
  multiValue: (base: any) => ({
    ...base,
    backgroundColor: "rgba(220, 38, 38, 0.2)", // subtle red
    borderRadius: "6px",
    padding: "2px 4px",
  }),

  multiValueLabel: (base: any) => ({
    ...base,
    color: "white",
    fontSize: "13px",
  }),

  multiValueRemove: (base: any) => ({
    ...base,
    color: "#f87171",
    cursor: "pointer",
    ":hover": {
      backgroundColor: "var(--accent-primary)",
      color: "white",
    },
  }),
};


export function StyledSelect<
  Option,
  IsMulti extends boolean = false,
  Group extends GroupBase<Option> = GroupBase<Option>
>(props: SelectProps<Option, IsMulti, Group>) {
  return (
    <Select
      {...props}
      styles={styles}
      classNamePrefix="styled-select"
    />
  );
}
