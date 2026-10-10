import pytest

from main import entity_for, merge_columns, parse_csv, parse_json


@pytest.mark.parametrize("name, entity", [
    ("source_data/Region 1/customers_2018.csv", "customers"),
    ("source_data/Region 1/customers_1.csv", "customers"),
    ("source_data/Region 6/returns_2026.json", "returns"),
    ("source_data/returns_2.json", "returns"),
    ("source_data/transactions_3.csv", "transactions"),
    ("source_data/products.json", "products"),
    ("source_data/vendors.csv", "vendors"),
    ("source_data/products.csv", None),       # wrong format for the entity
    ("source_data/README.md", None),
    ("source_data/Region 1/", None),
])
def test_entity_for(name, entity):
    assert entity_for(name) == entity


def test_parse_csv_lowercases_headers_and_nulls_empty_fields():
    columns, rows = parse_csv("CustomerID,Customer_Name,segment\nC1,,Consumer\n", "f.csv")
    assert columns == ["customerid", "customer_name", "segment"]
    assert rows == [{"customerid": "C1", "customer_name": None, "segment": "Consumer"}]


def test_parse_csv_keeps_quoted_commas_and_literal_null_text():
    _, rows = parse_csv('id,name\n1,"Smith, Jo"\n2,NULL\n', "f.csv")
    assert rows == [{"id": "1", "name": "Smith, Jo"}, {"id": "2", "name": "NULL"}]


def test_parse_csv_rejects_ragged_rows():
    with pytest.raises(ValueError, match="f.csv:2"):
        parse_csv("a,b\n1,2,3\n", "f.csv")


def test_parse_csv_rejects_columns_that_collide_when_lowercased():
    with pytest.raises(ValueError, match="collide"):
        parse_csv("Order_ID,order_id\n1,2\n", "f.csv")


def test_parse_json_array_keeps_number_text_and_unions_keys():
    text = '[{"OrderId": "A", "amount": 106.36}, {"OrderId": "B", "amount": 100.0, "Extra": true}]'
    columns, rows = parse_json(text, "f.json")
    assert columns == ["orderid", "amount", "extra"]
    assert rows == [
        {"orderid": "A", "amount": "106.36"},
        {"orderid": "B", "amount": "100.0", "extra": "true"},
    ]


def test_parse_json_nulls_ints_and_nested_values():
    _, rows = parse_json('[{"qty": 4, "dim": null, "tags": ["a", "b"]}]', "f.json")
    assert rows == [{"qty": "4", "dim": None, "tags": '["a","b"]'}]


def test_parse_json_accepts_ndjson():
    columns, rows = parse_json('{"a": 1}\n{"a": 2}\n', "f.json")
    assert columns == ["a"] and [r["a"] for r in rows] == ["1", "2"]


def test_merge_columns_appends_new_columns_in_order():
    assert merge_columns(["a", "b"], ["b", "c", "a", "d"]) == ["a", "b", "c", "d"]
