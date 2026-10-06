#property copyright "moeinalva"
#property link      "https://github.com/moeinalva"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

// -----------------------------------------------------------------------------
// MT5 Range Divider
//
// A chart-only utility. It records two prices from chart clicks and creates
// independent OBJ_HLINE levels for a two- or four-section range.
// -----------------------------------------------------------------------------

input group "Object namespace"
input string InpObjectPrefix = "HRD_";

input group "Boundary lines"
input color           InpBoundaryColor       = clrDeepSkyBlue;
input ENUM_LINE_STYLE InpBoundaryStyle       = STYLE_SOLID;
input int             InpBoundaryWidth       = 2;

input group "Divider lines"
input color           InpDividerColor        = clrOrange;
input ENUM_LINE_STYLE InpDividerStyle        = STYLE_DASH;
input int             InpDividerWidth        = 1;

input group "Generated object behavior"
input bool            InpLinesSelectable     = false;
input bool            InpHideGeneratedObjects = false;
input bool            InpDrawLinesInBackground = false;

input group "Selection preview"
input color           InpPreviewColor        = clrSilver;
input ENUM_LINE_STYLE InpPreviewStyle        = STYLE_DOT;
input int             InpPreviewWidth        = 1;

input group "Control panel"
input ENUM_BASE_CORNER InpPanelCorner        = CORNER_LEFT_UPPER;
input int              InpPanelX             = 8;
input int              InpPanelY             = 8;

enum RangeToolState
  {
   STATE_SELECTION_OFF = 0,
   STATE_WAITING_FOR_POINT_1,
   STATE_WAITING_FOR_POINT_2,
   STATE_WAITING_FOR_DIVISION,
   STATE_CREATING_RANGE
  };

long           g_chart_id                    = 0;
RangeToolState g_state                       = STATE_SELECTION_OFF;
bool           g_selection_enabled           = false;
bool           g_has_point_1                 = false;
bool           g_has_point_2                 = false;
double         g_point_1                     = 0.0;
double         g_point_2                     = 0.0;
int            g_selected_sections           = 0;
int            g_panel_x                     = 0;
int            g_panel_y                     = 0;
bool           g_previous_delete_event_state = false;
bool           g_is_deinitializing           = false;
bool           g_bulk_operation              = false;
bool           g_previous_mouse_move_state   = false;
bool           g_dragging                     = false;
bool           g_left_button_down             = false;
bool           g_suppress_drag_click          = false;
bool           g_previous_mouse_scroll        = true;
int            g_drag_mouse_x                 = 0;
int            g_drag_mouse_y                 = 0;
int            g_drag_panel_x                 = 0;
int            g_drag_panel_y                 = 0;

struct RangeRecord
  {
   int id;
   int sections;
  };
RangeRecord g_ranges[];

const int PANEL_WIDTH  = 360;
const int PANEL_HEIGHT = 168;
const int HEADER_HEIGHT = 24;
const int BUTTON_HEIGHT = 22;

// -----------------------------------------------------------------------------
// Naming helpers
// -----------------------------------------------------------------------------

string UiPrefix()
  {
   return InpObjectPrefix + "UI_";
  }

string RangePrefix()
  {
   return InpObjectPrefix + "Range_";
  }

string PreviewPrefix()
  {
   return InpObjectPrefix + "UI_Preview_";
  }

string UiPanelName()
  {
   return UiPrefix() + "Panel";
  }

string UiHeaderName()
  {
   return UiPrefix() + "Header";
  }

string UiStatusName()
  {
   return UiPrefix() + "Status";
  }

string UiSelectionName()
  {
   return UiPrefix() + "Selection";
  }

string UiSections2Name()
  {
   return UiPrefix() + "Sections_2";
  }

string UiSections4Name()
  {
   return UiPrefix() + "Sections_4";
  }

string UiCreateName()
  {
   return UiPrefix() + "Create";
  }

string UiCancelName()
  {
   return UiPrefix() + "Cancel";
  }

string UiClearName()
  {
   return UiPrefix() + "Clear_All";
  }

string UiClearSectionsName(const int sections)
  {
   return UiPrefix() + "Clear_" + IntegerToString(sections);
  }

string UiTitleName()
  {
   return UiPrefix() + "Title";
  }

string PreviewName(const int index)
  {
   return PreviewPrefix() + IntegerToString(index);
  }

string RangeObjectName(const int range_id,
                       const string role,
                       const int index)
  {
   return StringFormat("%s%06d_%s_%d",
                       RangePrefix(),
                       range_id,
                       role,
                       index);
  }

bool HasPrefix(const string value,
               const string prefix)
  {
   const int prefix_length = StringLen(prefix);
   return StringLen(value) >= prefix_length &&
          StringSubstr(value, 0, prefix_length) == prefix;
  }

// -----------------------------------------------------------------------------
// General helpers
// -----------------------------------------------------------------------------

void LogLastError(const string context)
  {
   const int error_code = GetLastError();
   PrintFormat("HRD: %s (error %d)", context, error_code);
   ResetLastError();
  }

int SafePanelCoordinate(const int coordinate)
  {
   return coordinate < 0 ? 0 : coordinate;
  }

void ClampPanelPosition(int &x,
                        int &y)
  {
   long chart_width = 0;
   long chart_height = 0;
   ChartGetInteger(g_chart_id, CHART_WIDTH_IN_PIXELS, 0, chart_width);
   ChartGetInteger(g_chart_id, CHART_HEIGHT_IN_PIXELS, 0, chart_height);

   x = SafePanelCoordinate(x);
   y = SafePanelCoordinate(y);

   if(chart_width > 0)
     {
      int maximum_x = (int)chart_width - PANEL_WIDTH;
      if(maximum_x < 0)
         maximum_x = 0;
      if(x > maximum_x)
         x = maximum_x;
     }

   if(chart_height > 0)
     {
      int maximum_y = (int)chart_height - PANEL_HEIGHT;
      if(maximum_y < 0)
         maximum_y = 0;
      if(y > maximum_y)
         y = maximum_y;
     }
  }

void InitializePanelPosition()
  {
   g_panel_x = SafePanelCoordinate(InpPanelX);
   g_panel_y = SafePanelCoordinate(InpPanelY);

   const string panel_name = UiPanelName();
   if(ObjectFind(g_chart_id, panel_name) >= 0 &&
      ObjectGetInteger(g_chart_id, panel_name, OBJPROP_TYPE) == OBJ_RECTANGLE_LABEL)
     {
      g_panel_x = (int)ObjectGetInteger(g_chart_id,
                                        panel_name,
                                        OBJPROP_XDISTANCE);
      g_panel_y = (int)ObjectGetInteger(g_chart_id,
                                        panel_name,
                                        OBJPROP_YDISTANCE);
     }

   if(ObjectFind(g_chart_id, panel_name) >= 0 &&
      ObjectGetInteger(g_chart_id, panel_name, OBJPROP_CORNER) == CORNER_LEFT_UPPER)
     {
      if(InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER)
         g_panel_x = (int)ChartGetInteger(g_chart_id, CHART_WIDTH_IN_PIXELS) - g_panel_x - PANEL_WIDTH;
      if(InpPanelCorner == CORNER_LEFT_LOWER || InpPanelCorner == CORNER_RIGHT_LOWER)
         g_panel_y = (int)ChartGetInteger(g_chart_id, CHART_HEIGHT_IN_PIXELS, 0) - g_panel_y - PANEL_HEIGHT;
     }
   ClampPanelPosition(g_panel_x, g_panel_y);
  }

void SetUiObjectPosition(const string name,
                         const int x,
                         const int y)
  {
   if(ObjectFind(g_chart_id, name) < 0)
      return;

   ObjectSetInteger(g_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(g_chart_id, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart_id, name, OBJPROP_YDISTANCE, y);
  }

// All UI objects use the same screen origin, including for right/lower corners.
void PanelScreenOrigin(int &left, int &top)
  {
   left = g_panel_x;
   top = g_panel_y;
   if(InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER)
      left = (int)ChartGetInteger(g_chart_id, CHART_WIDTH_IN_PIXELS) - g_panel_x - PANEL_WIDTH;
   if(InpPanelCorner == CORNER_LEFT_LOWER || InpPanelCorner == CORNER_RIGHT_LOWER)
      top = (int)ChartGetInteger(g_chart_id, CHART_HEIGHT_IN_PIXELS, 0) - g_panel_y - PANEL_HEIGHT;
   left = SafePanelCoordinate(left);
   top = SafePanelCoordinate(top);
  }

void UpdatePanelPositions()
  {
   ClampPanelPosition(g_panel_x, g_panel_y);
   int left, top;
   PanelScreenOrigin(left, top);
   SetUiObjectPosition(UiPanelName(), left, top);
   SetUiObjectPosition(UiHeaderName(), left, top);
   SetUiObjectPosition(UiTitleName(), left + 8, top + 5);
   SetUiObjectPosition(UiStatusName(), left + 8, top + 30);
   const int column_1 = left + 8;
   const int column_2 = left + 182;
   SetUiObjectPosition(UiSections2Name(), column_1, top + 52);
   SetUiObjectPosition(UiSections4Name(), column_2, top + 52);
   SetUiObjectPosition(UiCreateName(), column_1, top + 80);
   SetUiObjectPosition(UiCancelName(), column_2, top + 80);
   SetUiObjectPosition(UiClearSectionsName(2), column_1, top + 108);
   SetUiObjectPosition(UiClearSectionsName(4), column_2, top + 108);
   SetUiObjectPosition(UiClearName(), column_1, top + 136);
   SetUiObjectPosition(UiSelectionName(), column_2, top + 136);
  }

bool IsPointInsidePanel(const int x, const int y)
  {
   int left, top;
   PanelScreenOrigin(left, top);
   return x >= left && x <= left + PANEL_WIDTH &&
          y >= top && y <= top + PANEL_HEIGHT;
  }

bool IsPointInsideHeader(const int x, const int y)
  {
   int left, top;
   PanelScreenOrigin(left, top);
   return x >= left && x <= left + PANEL_WIDTH &&
          y >= top && y <= top + HEADER_HEIGHT;
  }

int SafeLineWidth(const int width)
  {
   if(width < 1)
      return 1;
   if(width > 5)
      return 5;
   return width;
  }

double SymbolTickSize()
  {
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tick_size <= 0.0)
      tick_size = MathPow(10.0, -_Digits);
   return tick_size;
  }

double NormalizePriceToTick(const double price)
  {
   const double tick_size = SymbolTickSize();
   if(tick_size <= 0.0)
      return NormalizeDouble(price, _Digits);

   const double tick_count = MathRound(price / tick_size);
   return NormalizeDouble(tick_count * tick_size, _Digits);
  }

bool PricesAreEqual(const double first_price,
                    const double second_price)
  {
   const double tolerance = SymbolTickSize() * 0.5;
   return MathAbs(first_price - second_price) <= tolerance;
  }

string FormatPrice(const double price)
  {
   return DoubleToString(price, _Digits);
  }

bool EnsureObjectType(const string name,
                      const ENUM_OBJECT object_type)
  {
   const int existing_subwindow = ObjectFind(g_chart_id, name);
   if(existing_subwindow >= 0)
     {
      const long existing_type = ObjectGetInteger(g_chart_id,
                                                   name,
                                                   OBJPROP_TYPE);
      if(existing_type != object_type)
        {
         PrintFormat("HRD: object name collision for '%s' (type %d, expected %d)",
                     name,
                     existing_type,
                     object_type);
         return false;
        }
      return true;
     }

   ResetLastError();
   if(!ObjectCreate(g_chart_id,
                    name,
                    object_type,
                    0,
                    (datetime)0,
                    0.0))
     {
      LogLastError("failed to create object '" + name + "'");
      return false;
     }
   return true;
  }

bool SetCommonObjectProperties(const string name,
                               const bool selectable,
                               const bool hidden,
                               const bool back)
  {
   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_SELECTABLE, selectable))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_SELECTED, false))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_HIDDEN, hidden))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_BACK, back))
      success = false;
   return success;
  }

bool ConfigureHorizontalLine(const string name,
                             const color line_color,
                             const ENUM_LINE_STYLE line_style,
                             const int line_width,
                             const bool selectable,
                             const bool hidden,
                             const bool back,
                             const string tooltip)
  {
   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_COLOR, line_color))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_STYLE, line_style))
      success = false;
   if(!ObjectSetInteger(g_chart_id,
                        name,
                        OBJPROP_WIDTH,
                        SafeLineWidth(line_width)))
      success = false;
   if(!SetCommonObjectProperties(name, selectable, hidden, back))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_TOOLTIP, tooltip))
      success = false;
   return success;
  }

// -----------------------------------------------------------------------------
// Status and panel
// -----------------------------------------------------------------------------

string StatusWithPoints(const string instruction)
  {
   const string point_1_text = g_has_point_1 ? FormatPrice(g_point_1) : "-";
   const string point_2_text = g_has_point_2 ? FormatPrice(g_point_2) : "-";
   return StringFormat("%s    P1: %s    P2: %s",
                       instruction,
                       point_1_text,
                       point_2_text);
  }

void SetStatus(const string message)
  {
   if(ObjectFind(g_chart_id, UiStatusName()) < 0)
      return;

   ObjectSetString(g_chart_id, UiStatusName(), OBJPROP_TOOLTIP, message);
   const string visible = StringLen(message) > 60 ? StringSubstr(message, 0, 57) + "..." : message;
   ObjectSetString(g_chart_id, UiStatusName(), OBJPROP_TEXT, visible);
   ChartRedraw(g_chart_id);
  }

void SetButtonAppearance(const string name,
                         const bool selected,
                         const bool enabled)
  {
   if(ObjectFind(g_chart_id, name) < 0)
      return;

   color background_color = clrGray;
   color text_color       = clrDarkGray;
   if(enabled)
     {
      background_color = selected ? clrDodgerBlue : clrDarkSlateGray;
      text_color       = clrWhite;
     }

   ObjectSetInteger(g_chart_id, name, OBJPROP_BGCOLOR, background_color);
   ObjectSetInteger(g_chart_id, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(g_chart_id, name, OBJPROP_BORDER_COLOR, clrSilver);
   ObjectSetInteger(g_chart_id, name, OBJPROP_STATE, selected);
  }

void UpdateButtonStates()
  {
   ObjectSetString(g_chart_id,
                   UiSelectionName(),
                   OBJPROP_TEXT,
                   g_selection_enabled ? "Disable selection" : "Enable selection");
   SetButtonAppearance(UiSelectionName(),
                       g_selection_enabled,
                       true);

   const bool range_ready = g_selection_enabled &&
                            g_has_point_1 &&
                            g_has_point_2;
   const bool can_create  = range_ready &&
                            (g_selected_sections == 2 ||
                             g_selected_sections == 4);

   SetButtonAppearance(UiSections2Name(),
                       g_selected_sections == 2,
                       range_ready);
   SetButtonAppearance(UiSections4Name(),
                       g_selected_sections == 4,
                       range_ready);
   SetButtonAppearance(UiCreateName(),
                       can_create,
                       can_create);
   SetButtonAppearance(UiCancelName(), false, true);
   SetButtonAppearance(UiClearName(), false, true);
   SetButtonAppearance(UiClearSectionsName(2), false, true);
   SetButtonAppearance(UiClearSectionsName(4), false, true);
  }

bool CreateOrUpdateLabel(const string name,
                         const string text,
                         const int x,
                         const int y,
                         const color text_color,
                         const int font_size)
  {
   if(!EnsureObjectType(name, OBJ_LABEL))
      return false;

   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_XDISTANCE, x))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_YDISTANCE, y))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_COLOR, text_color))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_FONTSIZE, font_size))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_FONT, "Arial"))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_TEXT, text))
      success = false;
   if(!SetCommonObjectProperties(name, false, true, false))
      success = false;
   return success;
  }

bool CreateOrUpdateButton(const string name,
                          const string text,
                          const int x,
                          const int y,
                          const int width)
  {
   if(!EnsureObjectType(name, OBJ_BUTTON))
      return false;

   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_XDISTANCE, x))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_YDISTANCE, y))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_XSIZE, width))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_YSIZE, BUTTON_HEIGHT))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_ZORDER, 100))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_FONTSIZE, 8))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_FONT, "Arial"))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_TEXT, text))
      success = false;
   if(!SetCommonObjectProperties(name, false, true, false))
      success = false;
   return success;
  }

bool CreateControlPanel()
  {
   if(!EnsureObjectType(UiPanelName(), OBJ_RECTANGLE_LABEL))
      return false;
   if(!EnsureObjectType(UiHeaderName(), OBJ_RECTANGLE_LABEL))
      return false;

   bool success = true;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_CORNER, CORNER_LEFT_UPPER))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_XSIZE, PANEL_WIDTH))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_YSIZE, PANEL_HEIGHT))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_BGCOLOR, clrBlack))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_COLOR, clrDimGray))
      success = false;
   // Keep the panel in the foreground so clicks inside its body do not fall
   // through and become price-selection clicks when selection is enabled.
   if(!SetCommonObjectProperties(UiPanelName(), false, true, false))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_ZORDER, 0))
      success = false;

   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_CORNER, CORNER_LEFT_UPPER))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_XSIZE, PANEL_WIDTH))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_YSIZE, HEADER_HEIGHT))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_BGCOLOR, clrBlack))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_COLOR, clrDimGray))
      success = false;
   if(!SetCommonObjectProperties(UiHeaderName(), false, true, false))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_ZORDER, 10))
      success = false;
   if(!ObjectSetString(g_chart_id,
                       UiHeaderName(),
                       OBJPROP_TOOLTIP,
                       "Drag to move the MT5 Range Divider panel"))
      success = false;

   if(!CreateOrUpdateLabel(UiTitleName(), "MT5 Range Divider  |  Drag to move", 0, 0, clrWhite, 9))
      success = false;
   if(!CreateOrUpdateLabel(UiStatusName(), "Selection OFF. Click Enable selection.", 0, 0, clrWhite, 8))
      success = false;
   if(!CreateOrUpdateButton(UiSections2Name(), "2 Sections", 0, 0, 170))
      success = false;
   if(!CreateOrUpdateButton(UiSections4Name(), "4 Sections", 0, 0, 170))
      success = false;
   if(!CreateOrUpdateButton(UiCreateName(), "Create", 0, 0, 170))
      success = false;
   if(!CreateOrUpdateButton(UiCancelName(), "Cancel", 0, 0, 170))
      success = false;
   if(!CreateOrUpdateButton(UiClearSectionsName(2), "Clear 2 Sections", 0, 0, 170))
      success = false;
   if(!CreateOrUpdateButton(UiClearSectionsName(4), "Clear 4 Sections", 0, 0, 170))
      success = false;
   if(!CreateOrUpdateButton(UiClearName(), "Clear All", 0, 0, 170))
      success = false;
   if(!CreateOrUpdateButton(UiSelectionName(), "Enable selection", 0, 0, 170))
      success = false;

   UpdatePanelPositions();
   UpdateButtonStates();
   return success;
  }

// -----------------------------------------------------------------------------
// Preview lines
// -----------------------------------------------------------------------------

bool CreateOrMovePreview(const int index,
                         const double price)
  {
   const string name = PreviewName(index);
   if(!EnsureObjectType(name, OBJ_HLINE))
      return false;

   const double normalized_price = NormalizePriceToTick(price);
   bool success = true;
   if(!ObjectSetDouble(g_chart_id,
                       name,
                       OBJPROP_PRICE,
                       0,
                       normalized_price))
      success = false;
   if(!ConfigureHorizontalLine(name,
                               InpPreviewColor,
                               InpPreviewStyle,
                               InpPreviewWidth,
                               false,
                               false,
                               false,
                               "HRD selection preview"))
      success = false;
   if(!success)
      LogLastError("failed to update preview line '" + name + "'");
   return success;
  }

void DeletePreviewLines()
  {
   ResetLastError();
   ObjectsDeleteAll(g_chart_id, PreviewPrefix());
   ResetLastError();
  }

// -----------------------------------------------------------------------------
// Range management
// -----------------------------------------------------------------------------

bool RangeIdHasAnyObject(const int range_id)
  {
   for(int boundary_index = 1; boundary_index <= 2; boundary_index++)
     {
      if(ObjectFind(g_chart_id,
                    RangeObjectName(range_id,
                                    "Boundary",
                                    boundary_index)) >= 0)
         return true;
     }

   for(int divider_index = 1; divider_index <= 3; divider_index++)
     {
      if(ObjectFind(g_chart_id,
                    RangeObjectName(range_id,
                                    "Divider",
                                    divider_index)) >= 0)
         return true;
     }
   return false;
  }

string RangeTypeName(const int range_id)
  {
   return RangeObjectName(range_id, "Type", 0);
  }

void RemoveRangeRecord(const int index)
  {
   const int count = ArraySize(g_ranges);
   for(int i = index; i < count - 1; i++)
      g_ranges[i] = g_ranges[i + 1];
   ArrayResize(g_ranges, count - 1);
  }

bool AppendRangeRecord(const int range_id, const int sections)
  {
   const int index = ArraySize(g_ranges);
   if(ArrayResize(g_ranges, index + 1) != index + 1)
      return false;
   g_ranges[index].id = range_id;
   g_ranges[index].sections = sections;
   return true;
  }

bool SaveRangeRecord(const int range_id, const int sections)
  {
   // A hidden, non-rendered chart object keeps explicit type metadata with
   // the persistent lines. It shares their namespace and unique range ID.
   const string name = RangeTypeName(range_id);
   if(!EnsureObjectType(name, OBJ_LABEL))
      return false;
   if(!SetCommonObjectProperties(name, false, true, true) ||
      !ObjectSetInteger(g_chart_id, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS) ||
      !ObjectSetString(g_chart_id, name, OBJPROP_TEXT, IntegerToString(sections)) ||
      !AppendRangeRecord(range_id, sections))
     {
      ObjectDelete(g_chart_id, name);
      return false;
     }
   return true;
  }

void RestoreRangeRecords()
  {
   ArrayResize(g_ranges, 0);
   const int total = ObjectsTotal(g_chart_id);
   for(int i = total - 1; i >= 0; i--)
     {
      const string name = ObjectName(g_chart_id, i);
      if(!HasPrefix(name, RangePrefix()))
         continue;
      const int range_id = (int)StringToInteger(StringSubstr(name, StringLen(RangePrefix()), 6));
      if(range_id <= 0 || name != RangeTypeName(range_id) ||
         ObjectGetInteger(g_chart_id, name, OBJPROP_TYPE) != OBJ_LABEL)
         continue;
      const string type_text = ObjectGetString(g_chart_id, name, OBJPROP_TEXT);
      if(type_text != "2" && type_text != "4")
         continue;
      if(!RangeIdHasAnyObject(range_id))
         ObjectDelete(g_chart_id, name);
      else if(!AppendRangeRecord(range_id, (int)StringToInteger(type_text)))
         PrintFormat("HRD: could not restore metadata for range %06d", range_id);
     }
  }

void PruneRangeRecords()
  {
   for(int i = ArraySize(g_ranges) - 1; i >= 0; i--)
     {
      if(RangeIdHasAnyObject(g_ranges[i].id))
         continue;
      ObjectDelete(g_chart_id, RangeTypeName(g_ranges[i].id));
      RemoveRangeRecord(i);
     }
  }

void ClearSectionRanges(const int sections)
  {
   g_bulk_operation = true;
   int cleared = 0;
   int failed = 0;
   for(int i = ArraySize(g_ranges) - 1; i >= 0; i--)
     {
      if(g_ranges[i].sections != sections)
         continue;
      const int range_id = g_ranges[i].id;
      DeleteRangeObjects(range_id);
      // Retain metadata if a line could not be deleted, so retry is safe.
      if(RangeIdHasAnyObject(range_id))
        {
         failed++;
         continue;
        }
      if(ObjectFind(g_chart_id, RangeTypeName(range_id)) >= 0 &&
         !ObjectDelete(g_chart_id, RangeTypeName(range_id)))
        {
         failed++;
         continue;
        }
      RemoveRangeRecord(i);
      cleared++;
     }
   g_bulk_operation = false;
   // Selective clearing leaves pending prices, previews and enable state intact.
   UpdateButtonStates();
   SetStatus(StatusWithPoints(StringFormat("Cleared %d %d-section ranges. Failed: %d.",
                                          cleared, sections, failed)));
   ChartRedraw(g_chart_id);
  }

int FindNextRangeId()
  {
   for(int candidate = 1; candidate < 1000000; candidate++)
     {
      if(!RangeIdHasAnyObject(candidate) &&
         ObjectFind(g_chart_id, RangeTypeName(candidate)) < 0)
         return candidate;
     }
   return -1;
  }

void DeleteRangeObjects(const int range_id)
  {
   for(int boundary_index = 1; boundary_index <= 2; boundary_index++)
      ObjectDelete(g_chart_id,
                   RangeObjectName(range_id,
                                   "Boundary",
                                   boundary_index));

   for(int divider_index = 1; divider_index <= 3; divider_index++)
      ObjectDelete(g_chart_id,
                   RangeObjectName(range_id,
                                   "Divider",
                                   divider_index));
  }

bool CalculateRangeLevels(const int sections,
                          double &levels[])
  {
   if(sections != 2 && sections != 4)
      return false;

   ArrayResize(levels, sections + 1);
   for(int index = 0; index <= sections; index++)
     {
      const double fraction = (double)index / (double)sections;
      levels[index] = NormalizePriceToTick(g_point_1 +
                                           (g_point_2 - g_point_1) *
                                           fraction);
     }
   return true;
  }

bool LevelsContainOverlap(const double &levels[])
  {
   const int level_count = ArraySize(levels);
   for(int first = 0; first < level_count; first++)
     {
      for(int second = first + 1; second < level_count; second++)
        {
         if(PricesAreEqual(levels[first], levels[second]))
            return true;
        }
     }
   return false;
  }

bool CreateRangeLine(const string name,
                     const double price,
                     const color line_color,
                     const ENUM_LINE_STYLE line_style,
                     const int line_width,
                     const string tooltip)
  {
   if(ObjectFind(g_chart_id, name) >= 0)
     {
      PrintFormat("HRD: refusing to overwrite existing object '%s'", name);
      return false;
     }

   ResetLastError();
   if(!ObjectCreate(g_chart_id,
                    name,
                    OBJ_HLINE,
                    0,
                    (datetime)0,
                    NormalizePriceToTick(price)))
     {
      LogLastError("failed to create range line '" + name + "'");
      return false;
     }

   if(!ConfigureHorizontalLine(name,
                               line_color,
                               line_style,
                               line_width,
                               InpLinesSelectable,
                               InpHideGeneratedObjects,
                               InpDrawLinesInBackground,
                               tooltip))
     {
      LogLastError("failed to configure range line '" + name + "'");
      return false;
     }
   return true;
  }

bool CreateRange(const int sections,
                 int &created_range_id,
                 bool &levels_overlap)
  {
   created_range_id = -1;
   levels_overlap  = false;

   if(!g_has_point_1 || !g_has_point_2)
      return false;
   if(sections != 2 && sections != 4)
      return false;
   if(PricesAreEqual(g_point_1, g_point_2))
      return false;

   double levels[];
   if(!CalculateRangeLevels(sections, levels))
      return false;

   levels_overlap = LevelsContainOverlap(levels);
   const int range_id = FindNextRangeId();
   if(range_id < 0)
     {
      Print("HRD: no available range ID remains");
      return false;
     }

   bool success = true;
   success = CreateRangeLine(
      RangeObjectName(range_id, "Boundary", 1),
      levels[0],
      InpBoundaryColor,
      InpBoundaryStyle,
      InpBoundaryWidth,
      StringFormat("HRD range %06d boundary 1", range_id)) && success;

   success = CreateRangeLine(
      RangeObjectName(range_id, "Boundary", 2),
      levels[sections],
      InpBoundaryColor,
      InpBoundaryStyle,
      InpBoundaryWidth,
      StringFormat("HRD range %06d boundary 2", range_id)) && success;

   for(int divider_index = 1;
       divider_index < sections;
       divider_index++)
     {
      const string divider_name = RangeObjectName(range_id,
                                                   "Divider",
                                                   divider_index);
      const bool divider_created = CreateRangeLine(
         divider_name,
         levels[divider_index],
         InpDividerColor,
         InpDividerStyle,
         InpDividerWidth,
         StringFormat("HRD range %06d divider %d",
                      range_id,
                      divider_index));
      success = divider_created && success;
     }

   if(!success)
     {
      DeleteRangeObjects(range_id);
      return false;
     }

   if(!SaveRangeRecord(range_id, sections))
     {
      DeleteRangeObjects(range_id);
      LogLastError("failed to save range type");
      return false;
     }
   created_range_id = range_id;
   return true;
  }

void ClearCurrentSelection()
  {
   DeletePreviewLines();
   g_has_point_1       = false;
   g_has_point_2       = false;
   g_point_1           = 0.0;
   g_point_2           = 0.0;
   g_selected_sections = 0;
   g_state             = g_selection_enabled
                         ? STATE_WAITING_FOR_POINT_1
                         : STATE_SELECTION_OFF;
   UpdateButtonStates();
  }

void ClearAllRanges()
  {
   g_bulk_operation = true;
   ResetLastError();
   const int deleted_ranges = ObjectsDeleteAll(g_chart_id, RangePrefix());
   const int deleted_preview = ObjectsDeleteAll(g_chart_id, PreviewPrefix());
   RestoreRangeRecords();
   ResetLastError();
   g_selection_enabled = false;
   ClearCurrentSelection();
   g_bulk_operation = false;

   SetStatus(StringFormat("Cleared %d range objects and %d preview objects. Selection OFF. Click Enable selection.",
                          deleted_ranges,
                          deleted_preview));
   ChartRedraw(g_chart_id);
  }

// -----------------------------------------------------------------------------
// Interaction handling
// -----------------------------------------------------------------------------

void HandleChartClick(const long x_coordinate,
                      const long y_coordinate)
  {
   // A button/object click can also arrive as CHARTEVENT_CLICK on some
   // terminal builds. Consume every click inside the panel before doing any
   // price conversion so UI clicks can never become Point 1 or Point 2.
   if(g_dragging || g_suppress_drag_click || IsPointInsidePanel((int)x_coordinate, (int)y_coordinate))
      return;

   if(!g_selection_enabled || g_state == STATE_SELECTION_OFF)
      return;

   int sub_window = 0;
   datetime click_time = 0;
   double clicked_price = 0.0;
   ResetLastError();
   if(!ChartXYToTimePrice(g_chart_id,
                          (int)x_coordinate,
                          (int)y_coordinate,
                          sub_window,
                          click_time,
                          clicked_price))
     {
      LogLastError("could not convert chart click to a price");
      SetStatus("Click conversion failed. Try inside the main price chart.");
      return;
     }

   // The time returned above is intentionally unused. This utility is price-only.
   if(sub_window != 0)
     {
      SetStatus("Click inside the main price chart window.");
      return;
     }

   clicked_price = NormalizePriceToTick(clicked_price);

   if(g_state == STATE_WAITING_FOR_POINT_1)
     {
      g_point_1     = clicked_price;
      g_point_2     = 0.0;
      g_has_point_1 = true;
      g_has_point_2 = false;
      g_selected_sections = 0;
      DeletePreviewLines();
      CreateOrMovePreview(1, g_point_1);
      g_state = STATE_WAITING_FOR_POINT_2;
      UpdateButtonStates();
      SetStatus(StatusWithPoints("Point 1 selected. Click point 2."));
      return;
     }

   if(g_state == STATE_WAITING_FOR_POINT_2)
     {
      if(PricesAreEqual(g_point_1, clicked_price))
        {
         SetStatus(StatusWithPoints("Point 2 matches point 1. Click a different price."));
         return;
        }

      g_point_2     = clicked_price;
      g_has_point_2 = true;
      CreateOrMovePreview(2, g_point_2);
      g_state = STATE_WAITING_FOR_DIVISION;
      UpdateButtonStates();
      SetStatus(StatusWithPoints("Choose 2 or 4 sections, then Create."));
      return;
     }

   if(g_state == STATE_WAITING_FOR_DIVISION)
     {
      SetStatus(StatusWithPoints("Choose a section count or Cancel before starting again."));
      return;
     }

   SetStatus("Creating range. Please wait...");
  }

void HandleButtonClick(const string object_name)
  {
   if(ObjectFind(g_chart_id, object_name) >= 0)
      ObjectSetInteger(g_chart_id, object_name, OBJPROP_STATE, false);

   if(object_name == UiSelectionName())
     {
      g_selection_enabled = !g_selection_enabled;
      ClearCurrentSelection();
      if(g_selection_enabled)
         SetStatus("Selection ON. Click first price.");
      else
         SetStatus("Selection OFF. Existing ranges are unchanged.");
      ChartRedraw(g_chart_id);
      return;
     }

   if(object_name == UiSections2Name() || object_name == UiSections4Name())
     {
      if(!g_selection_enabled)
        {
         SetStatus("Selection OFF. Click Enable selection first.");
         return;
        }
      if(!g_has_point_1 || !g_has_point_2)
        {
         SetStatus(StatusWithPoints("Select both prices before choosing sections."));
         return;
        }

      g_selected_sections = object_name == UiSections2Name() ? 2 : 4;
      g_state = STATE_WAITING_FOR_DIVISION;
      UpdateButtonStates();
      SetStatus(StatusWithPoints(StringFormat("%d sections selected. Press Create.",
                                               g_selected_sections)));
      return;
     }

   if(object_name == UiCreateName())
     {
      if(!g_selection_enabled)
        {
         SetStatus("Selection OFF. Click Enable selection first.");
         return;
        }
      if(!g_has_point_1 || !g_has_point_2)
        {
         SetStatus(StatusWithPoints("Select two prices before creating a range."));
         return;
        }
      if(g_selected_sections != 2 && g_selected_sections != 4)
        {
         SetStatus(StatusWithPoints("Choose 2 or 4 sections first."));
         return;
        }

      g_state = STATE_CREATING_RANGE;
      UpdateButtonStates();

      int created_range_id = -1;
      bool levels_overlap = false;
      if(!CreateRange(g_selected_sections,
                      created_range_id,
                      levels_overlap))
        {
         g_state = STATE_WAITING_FOR_DIVISION;
         UpdateButtonStates();
         SetStatus(StatusWithPoints("Range creation failed; selection retained. Retry or Cancel."));
         return;
        }

      const string overlap_note = levels_overlap
                                  ? " Some levels overlap at tick precision."
                                  : "";
      ClearCurrentSelection();
      SetStatus(StringFormat("Range %06d created.%s Click first price for the next range.",
                             created_range_id,
                             overlap_note));
      ChartRedraw(g_chart_id);
      return;
     }

   if(object_name == UiCancelName())
     {
      ClearCurrentSelection();
      SetStatus(g_selection_enabled
                ? "Selection cancelled. Click first price."
                : "Selection OFF. Click Enable selection.");
      ChartRedraw(g_chart_id);
      return;
     }

   if(object_name == UiClearSectionsName(2) || object_name == UiClearSectionsName(4))
     {
      ClearSectionRanges(object_name == UiClearSectionsName(2) ? 2 : 4);
      return;
     }

   if(object_name == UiClearName())
     {
     ClearAllRanges();
     return;
     }
  }

void EndPanelDrag()
  {
   if(!g_dragging)
      return;
   g_dragging = false;
   ChartSetInteger(g_chart_id, CHART_MOUSE_SCROLL, g_previous_mouse_scroll);
  }

void HandlePanelMouse(const int x, const int y, const string buttons)
  {
   const bool left_down = (StringToInteger(buttons) & 1) != 0;
   if(left_down && !g_left_button_down)
     {
      // A fresh press starts a new gesture and retires any old release guard.
      g_suppress_drag_click = false;
      if(IsPointInsideHeader(x, y))
        {
         g_dragging = true;
         g_suppress_drag_click = true;
         g_drag_mouse_x = x;
         g_drag_mouse_y = y;
         g_drag_panel_x = g_panel_x;
         g_drag_panel_y = g_panel_y;
         g_previous_mouse_scroll = ChartGetInteger(g_chart_id, CHART_MOUSE_SCROLL) != 0;
         ChartSetInteger(g_chart_id, CHART_MOUSE_SCROLL, false);
        }
     }
   if(g_dragging)
     {
      const int x_sign = (InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER) ? -1 : 1;
      const int y_sign = (InpPanelCorner == CORNER_LEFT_LOWER || InpPanelCorner == CORNER_RIGHT_LOWER) ? -1 : 1;
      g_panel_x = g_drag_panel_x + x_sign * (x - g_drag_mouse_x);
      g_panel_y = g_drag_panel_y + y_sign * (y - g_drag_mouse_y);
      UpdatePanelPositions();
      ChartRedraw(g_chart_id);
      if(!left_down)
         EndPanelDrag();
     }
   g_left_button_down = left_down;
  }

void HandleObjectDelete(const string object_name)
  {
   if(g_is_deinitializing || g_bulk_operation)
      return;

   // Preview objects intentionally share the UI namespace, but deleting a
   // preview must not be mistaken for deleting the control panel itself.
   if(HasPrefix(object_name, PreviewPrefix()))
      return;

   if(HasPrefix(object_name, RangePrefix()))
     {
      PruneRangeRecords();
      SetStatus("One generated line was deleted; other ranges remain unchanged.");
      return;
     }

   if(HasPrefix(object_name, UiPrefix()))
     {
      CreateControlPanel();
      SetStatus(StatusWithPoints("Control panel restored."));
     }
  }

// -----------------------------------------------------------------------------
// MQL5 event handlers
// -----------------------------------------------------------------------------

int OnInit()
  {
   // MQL5 chart object names are limited to 63 characters. The longest
   // generated range name needs 23 characters after the configured prefix.
   if(StringLen(InpObjectPrefix) == 0 ||
      StringLen(InpObjectPrefix) > 40 ||
      StringFind(InpObjectPrefix, "*") >= 0)
     {
      Print("HRD: InpObjectPrefix must be 1-40 characters and must not contain '*'.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_chart_id          = ChartID();
   g_state             = STATE_SELECTION_OFF;
   g_selection_enabled = false;
   g_has_point_1       = false;
   g_has_point_2       = false;
   g_selected_sections = 0;
   g_is_deinitializing = false;
   g_bulk_operation    = false;
   g_dragging = false;
   g_left_button_down = false;
   g_suppress_drag_click = false;
   InitializePanelPosition();
   RestoreRangeRecords();
   g_previous_mouse_move_state = ChartGetInteger(g_chart_id, CHART_EVENT_MOUSE_MOVE) != 0;
   if(!ChartSetInteger(g_chart_id, CHART_EVENT_MOUSE_MOVE, true))
     {
      LogLastError("could not enable panel mouse events");
      return INIT_FAILED;
     }

   long previous_delete_event_state = 0;
   if(ChartGetInteger(g_chart_id,
                     CHART_EVENT_OBJECT_DELETE,
                     0,
                     previous_delete_event_state))
      g_previous_delete_event_state = previous_delete_event_state != 0;
   else
      g_previous_delete_event_state = false;

   if(!ChartSetInteger(g_chart_id, CHART_EVENT_OBJECT_DELETE, true))
      LogLastError("could not enable object-delete notifications");

   if(!CreateControlPanel())
     {
      Print("HRD: failed to create the control panel.");
      return INIT_FAILED;
     }

   SetStatus("Selection OFF. Click Enable selection.    P1: -    P2: -");
   ChartRedraw(g_chart_id);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   g_is_deinitializing = true;
   EndPanelDrag();
   ChartSetInteger(g_chart_id, CHART_EVENT_MOUSE_MOVE, g_previous_mouse_move_state);

   // Permanent range lines intentionally survive indicator removal,
   // timeframe changes, and re-attachment. During a timeframe change, keep
   // the panel objects themselves so their dragged pixel position survives
   // the indicator reinitialization; transient previews are still removed.
   ResetLastError();
   if(reason == REASON_CHARTCHANGE)
      ObjectsDeleteAll(g_chart_id, PreviewPrefix());
   else
      ObjectsDeleteAll(g_chart_id, UiPrefix());
   ResetLastError();

   if(g_chart_id != 0)
      ChartSetInteger(g_chart_id,
                     CHART_EVENT_OBJECT_DELETE,
                     g_previous_delete_event_state);
   ChartRedraw(g_chart_id);
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      HandlePanelMouse((int)lparam, (int)dparam, sparam);
      return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(g_dragging || g_suppress_drag_click)
         return;
      if(HasPrefix(sparam, UiPrefix()))
         HandleButtonClick(sparam);
      return;
     }

   if(id == CHARTEVENT_OBJECT_DELETE)
     {
      HandleObjectDelete(sparam);
      return;
     }

   // Handle chart price clicks last. UI events above are consumed first, and
   // HandleChartClick() independently rejects coordinates inside the panel.
   if(id == CHARTEVENT_CLICK)
     {
      HandleChartClick(lparam, (long)dparam);
      return;
     }

   if(id == CHARTEVENT_KEYDOWN && lparam == 27 && g_selection_enabled)
     {
      ClearCurrentSelection();
      SetStatus("Selection cancelled. Click first price.");
      return;
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      UpdatePanelPositions();
      ChartRedraw(g_chart_id);
      return;
     }
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   return rates_total;
  }
