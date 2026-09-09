# MT5 Range Divider

A lightweight MetaTrader 5 custom indicator for marking independent price ranges and dividing each range into two or four equal horizontal sections.

## Installation

Copy `MT5RangeDivider.mq5` into the terminal's `MQL5/Indicators` folder, compile it in MetaEditor, and attach `MT5 Range Divider` to a chart. The generated `HRD_Range_...` lines intentionally remain when the indicator is removed or the timeframe changes.

## Architecture

The tool is implemented as a chart-window custom indicator. It has no trading logic and uses native chart objects for both the compact control panel and the generated levels.

### State machine

```text
SELECTION_OFF
        |
        | Enable selection
        v
WAITING_FOR_POINT_1
        |
        | chart click -> store normalized price 1
        v
WAITING_FOR_POINT_2
        |
        | chart click -> store normalized price 2
        v
WAITING_FOR_DIVISION
        |
        | choose 2 or 4 sections, then Create
        v
CREATE_RANGE
        |
        | successful creation or safe rollback
        v
WAITING_FOR_POINT_1
```

The runtime starts in `SELECTION_OFF`. The `Enable selection` button moves it to `WAITING_FOR_POINT_1`; disabling selection or using `Clear all` returns it to `SELECTION_OFF`. `Cancel` clears the current incomplete selection while preserving the enabled mode. A range is never recalculated from time; the X-coordinate and converted time are intentionally discarded after `ChartXYToTimePrice()` returns the price.

### User interaction

The indicator creates a small floating panel containing:

- `Enable selection` / `Disable selection` to control whether chart clicks are accepted;
- `2 sections` and `4 sections` selection buttons;
- `Create` to commit the selected range;
- `Cancel` to discard the current incomplete selection;
- `Clear all` to remove only this tool's ranges.

Drag the panel header to move the complete dashboard. The position is clamped to the chart and retained across chart redraws and timeframe changes. The two selected prices are shown as temporary horizontal preview lines. After creation, the preview is removed and the enabled indicator immediately waits for another pair of clicks.

### Range storage and naming

Generated lines are the persistent source of truth. No range depends on a runtime array, so existing ranges remain intact if the indicator is reloaded or the chart timeframe changes.

The default namespace is:

```text
HRD_Range_000001_Boundary_1
HRD_Range_000001_Boundary_2
HRD_Range_000001_Divider_1
...
```

The next available numeric ID is found by checking the chart for all possible names in the candidate range. This avoids collisions with surviving objects or a partially deleted range.

### Price calculation

For a selected pair `p1` and `p2`, the divider prices are calculated as:

```text
2 sections: p1 + (p2 - p1) / 2
4 sections: p1 + (p2 - p1) / 4
             p1 + (p2 - p1) / 2
             p1 + 3 * (p2 - p1) / 4
```

Every result is rounded to the symbol's `SYMBOL_TRADE_TICK_SIZE` and `_Digits`. The formulas work in either price direction.

### MQL5 events and functions

- `OnInit()` creates the panel and enables object-delete notifications.
- `OnChartEvent()` handles gated chart clicks, panel button clicks, panel dragging, chart changes, and manual deletion notifications.
- `CHARTEVENT_OBJECT_DRAG` moves the panel header and repositions every UI child as one group.
- `ChartXYToTimePrice()` converts click pixels to a chart price.
- `ObjectCreate(..., OBJ_HLINE, ...)` creates all range levels.
- `ObjectsDeleteAll()` with the tool's prefixes performs scoped cleanup.
- `OnDeinit()` removes only the panel and temporary preview objects; permanent range lines are deliberately preserved.

### Limitations and edge behavior

- A click in a non-main chart subwindow is ignored because the tool is price-chart-only.
- Chart clicks are ignored while selection is off; panel and button object events are handled separately from price selection.
- `Clear all` deletes this tool's range and preview objects, clears both selected prices and pending division state, and leaves selection off without creating a default line.
- The configurable object prefix is limited to 40 characters so generated MQL5 object names stay within the platform's 63-character limit.
- Two equal normalized prices are rejected as a zero-width range.
- If a range is smaller than the symbol's tick precision, multiple mathematical levels can normalize to the same displayed price. The requested objects are still created with distinct names and the status label reports the overlap.
- The default generated lines are fixed (`OBJPROP_SELECTABLE=false`) so ordinary clicks remain reliable. Their visibility in the Objects list and other line properties are configurable inputs.
- If a user deletes one generated line manually, the remaining lines are not modified; the status label reports the deletion and `Clear all` still removes every remaining object with the tool prefix.
