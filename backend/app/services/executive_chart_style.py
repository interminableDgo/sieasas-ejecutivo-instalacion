"""Export counterpart of core/theme.dart and widgets/executive_charts.dart.

Keep the dashboard's series order, colours and five-category donut grouping.
The report layout is deliberately independent of these chart conventions.
"""

BLUE = '12A5E5'
ORANGE = 'FF8300'
INK = '1B2A33'
MUTED = '5B6B74'
PALETTE = (BLUE, ORANGE, '4E7D67', '8064A2', 'D76770', '87949B')
DONUT_KEYS = ('apoyos', 'grupos')


def donut_rows(rows):
    return list(rows[:5])


def category_total(report, key):
    # The vulnerable-group widget uses the classified population as its base.
    return (sum(count for _, count in report['groups'][key])
            if key == 'grupos' else report['total'])


def category_chart_type(report, key):
    mode = report.get('chart_types', {}).get(key, 'donut')
    if mode == 'stacked':
        rows = report['groups'][key]
        if sum(count for _, count in rows) != category_total(report, key) or any(count < 0 for _, count in rows):
            return 'donut'  # Same compatibility rule as the dashboard.
    return mode


def treemap_rects(values, x=0, y=0, width=1, height=1, offset=0):
    total = sum(values)
    if total <= 0:
        return []
    if len(values) == 1:
        return [(offset, x, y, width, height)]
    mid = len(values)//2
    fraction = sum(values[:mid])/total
    if width >= height:
        cut = width*fraction
        return (treemap_rects(values[:mid], x, y, cut, height, offset) +
                treemap_rects(values[mid:], x+cut, y, width-cut, height, offset+mid))
    cut = height*fraction
    return (treemap_rects(values[:mid], x, y, width, cut, offset) +
            treemap_rects(values[mid:], x, y+cut, width, height-cut, offset+mid))
