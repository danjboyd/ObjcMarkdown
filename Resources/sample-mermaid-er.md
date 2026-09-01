# Storefront Schema

A sample entity-relationship diagram. Mermaid `erDiagram` blocks are drawn in the
preview; switch `View -> Diagram Rendering -> Diagram Source` to read the source
instead.

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    CUSTOMER ||--o{ ADDRESS : "ships to"
    ORDER ||--|{ ORDER_ITEM : contains
    ORDER ||--o| PAYMENT : "settled by"
    PRODUCT ||--o{ ORDER_ITEM : "appears in"
    CATEGORY ||--o{ PRODUCT : groups

    CUSTOMER {
        uuid id PK
        text email UK
        text full_name
    }
    ADDRESS {
        uuid id PK
        uuid customer_id FK
        text city
        char country
    }
    ORDER {
        uuid id PK
        uuid customer_id FK
        text status
        numeric total_cents
    }
    ORDER_ITEM {
        uuid id PK
        uuid order_id FK
        uuid product_id FK
        int quantity
    }
    PRODUCT {
        uuid id PK
        text sku UK "stock code"
        numeric price_cents
        bool active
    }
    CATEGORY {
        uuid id PK
        text slug UK
    }
    PAYMENT {
        uuid id PK
        uuid order_id FK
        text provider
        text status
    }
```

## Reading The Notation

Each end of a relationship carries a marker: a bar for one, a crow's foot for
many, and a circle when the end is optional.

| Notation | Reads as | In this schema |
| --- | --- | --- |
| `\|\|--o{` | one to zero-or-many | a customer may have no orders yet |
| `\|\|--\|{` | one to one-or-many | an order always has at least one line item |
| `\|\|--o\|` | one to zero-or-one | an order is settled by at most one payment |

## Fallback Behavior

Other mermaid diagram types render as ordinary code blocks:

```mermaid
flowchart LR
    A --> B
```

So does an `erDiagram` that cannot be parsed, with a diagnostic naming the line:

```mermaid
erDiagram
    A {
        lonely
    }
```
